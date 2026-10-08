// A tiny web server that runs inside the Mac app, only on this computer (127.0.0.1).
// It does the same job as bin/lectern.js, so the app shows the same pages that the
// Node version shows: the library, the presenter view, and the audience window.
import Foundation
import Network

final class Server {
    let library: URL          // the folder that holds the decks (~/Lectern)
    let appDir: URL           // the web pages (presenter.html and so on)
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "lectern.server")
    private(set) var port: UInt16 = 0

    init(library: URL, appDir: URL) {
        self.library = library
        self.appDir = appDir
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }

    /// Starts the server and calls `ready` with the port once it listens.
    func start(ready: @escaping (UInt16) -> Void) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let p = l.port?.rawValue {
                self?.port = p
                DispatchQueue.main.async { ready(p) }
            }
        }
        l.start(queue: queue)
        listener = l
    }

    // ---------- reading one request ----------

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data { buf.append(data) }
            if let req = Request.parse(buf) {
                let res = self.handle(req)
                c.send(content: res.bytes(), completion: .contentProcessed { _ in c.cancel() })
            } else if done || error != nil {
                c.cancel()
            } else {
                self.receive(c, buffer: buf)
            }
        }
    }

    // ---------- the routes (same as bin/lectern.js) ----------

    private func handle(_ req: Request) -> Response {
        let parts = req.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .map { String($0).removingPercentEncoding ?? String($0) }
        let first = parts.first ?? "", name = parts.count > 1 ? parts[1] : ""

        if req.path == "/" { return file(appDir.appendingPathComponent("home.html")) }
        if first == "present", deckDir(name) != nil { return file(appDir.appendingPathComponent("presenter.html")) }
        if first == "audience", deckDir(name) != nil { return file(appDir.appendingPathComponent("audience.html")) }
        if req.path == "/_lectern/adapter.js" { return file(appDir.appendingPathComponent("adapter.js")) }

        if first == "api" {
            let what = name, deck = parts.count > 2 ? parts[2] : ""
            if what == "decks" {
                // For the project list: kind of project and when it last changed (newest first).
                let list = listDecks().map { n -> [String: Any] in
                    let entry = deckEntry(n), dir = deckDir(n)
                    var modified = 0.0
                    if let dir = dir, let d = try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate { modified = d.timeIntervalSince1970 * 1000 }
                    var kind = "empty"; var slides: Any = NSNull()
                    switch entry {
                    case .html(let f)?:
                        kind = "html"
                        if let dir = dir, let d = try? dir.appendingPathComponent(f).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate { modified = max(modified, d.timeIntervalSince1970 * 1000) }
                    case .images(let imgs)?: kind = "images"; slides = imgs.count
                    case nil: break
                    }
                    return ["name": n, "ok": entry != nil, "kind": kind, "slides": slides, "modified": modified]
                }.sorted { ($0["modified"] as! Double) > ($1["modified"] as! Double) }
                return .json(["library": library.path, "decks": list])
            }
            if what == "new" && req.method == "POST" {
                // POST /api/new/<name>: make an empty project folder.
                let n = deck.trimmingCharacters(in: .whitespaces)
                guard safeName(n) else { return .text(400, "Please use a name without slashes.") }
                let dir = library.appendingPathComponent(n)
                if FileManager.default.fileExists(atPath: dir.path) { return .text(409, "A project with that name already exists.") }
                do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false) } catch { return .text(500, error.localizedDescription) }
                return .json(["ok": true, "name": n])
            }
            if what == "upload" && req.method == "PUT" {
                // PUT /api/upload/<deck>/<path inside the deck> with the file as the body
                guard safeName(deck) else { return .text(400, "Bad deck name") }
                let relParts = Array(parts.dropFirst(3))
                let rel = relParts.joined(separator: "/")
                let dir = library.appendingPathComponent(deck)
                guard !rel.isEmpty, !relParts.contains(where: { $0.hasPrefix(".") }), let target = inside(dir, rel) else {
                    return .text(400, "Bad path")
                }
                do {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try req.body.write(to: target)
                    return .json(["ok": true])
                } catch { return .text(500, error.localizedDescription) }
            }
            guard deckDir(deck) != nil else { return .text(404, "No such deck") }
            if what == "notes" && req.method == "GET" {
                let (notes, labels) = readNotes(deck)
                return .json(["notes": notes, "labels": labels])
            }
            if what == "version" { return .json(deckVersion(deck)) }
            if what == "order" && req.method == "PUT" {
                // { order: [old slide index, ...] } puts the slides in a new order. Content does not change.
                guard let body = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
                      let raw = body["order"] as? [Any] else { return .text(400, "Bad order") }
                let order = raw.map { ($0 as? NSNumber).flatMap { n -> Int? in Double(n.intValue) == n.doubleValue ? n.intValue : nil } ?? -1 }
                do { try reorderDeck(deck, order) } catch { return .text(409, "\(error)") }
                return .json(["ok": true])
            }
            if what == "notes" && req.method == "PUT" {
                guard let body = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
                    return .text(400, "Bad notes")
                }
                var (notes, labels) = readNotes(deck)
                if let outline = body["outline"] as? [Any] {
                    for (i, label) in outline.enumerated() { labels[String(i + 1)] = "\(label)" }
                    let fresh = !FileManager.default.fileExists(atPath: notesPath(deck).path)
                    writeNotes(deck, notes, labels, outline.count, body["title"] as? String ?? "")
                    return .json(["ok": true, "created": fresh])
                }
                let slide = (body["slide"] as? NSNumber)?.intValue ?? Int("\(body["slide"] ?? "")") ?? 0
                notes[String(slide)] = "\(body["text"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                writeNotes(deck, notes, labels, 0, readTitle(deck))
                return .json(["ok": true])
            }
        }

        if first == "deck", let dir = deckDir(name) {
            let rel = parts.dropFirst(2).joined(separator: "/")
            if rel.isEmpty {
                guard let entry = deckEntry(name) else { return .text(404, "This deck has no .html file and no images.") }
                switch entry {
                case .html(let f): return file(dir.appendingPathComponent(f), inject: true)
                case .images(let imgs):
                    return Response(status: 200, type: Self.types["html"]!, body: Data(injectAdapter(imageDeckHtml(name, imgs)).utf8))
                }
            }
            guard let target = inside(dir, rel) else { return .text(403, "Forbidden") }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
                return file(target.appendingPathComponent("index.html"), inject: true)
            }
            return file(target, inject: true)
        }
        return .text(404, "Not found")
    }

    // ---------- decks ----------

    enum Entry { case html(String), images([String]) }
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "avif", "svg"]

    func safeName(_ n: String) -> Bool {
        !n.isEmpty && !n.contains("/") && !n.contains("\\") && !n.hasPrefix(".")
    }
    /// A library entry is a folder, or a link to one HTML file (an imported file).
    func linkedFile(_ name: String) -> URL? {
        guard safeName(name) else { return nil }
        let real = library.appendingPathComponent(name).resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir), !isDir.boolValue,
              ["html", "htm"].contains(real.pathExtension.lowercased()) else { return nil }
        return real
    }
    func deckDir(_ name: String) -> URL? {
        guard safeName(name) else { return nil }
        if let file = linkedFile(name) { return file.deletingLastPathComponent() }
        let dir = library.appendingPathComponent(name)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue ? dir : nil
    }
    func listDecks() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        // deckDir follows links, so a linked deck folder counts too
        return items.map { $0.lastPathComponent }.filter { deckDir($0) != nil }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func deckEntry(_ name: String) -> Entry? {
        if let file = linkedFile(name) { return .html(file.lastPathComponent) }
        guard let dir = deckDir(name) else { return nil }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let htmls = files.filter { ["html", "htm"].contains(($0 as NSString).pathExtension.lowercased()) }
        if !htmls.isEmpty { return .html(htmls.contains("index.html") ? "index.html" : htmls[0]) }
        var images = files.filter { Self.imageExts.contains(($0 as NSString).pathExtension.lowercased()) }
        // slides.txt (one file name per line) sets the order, after a reorder.
        if let list = try? String(contentsOf: dir.appendingPathComponent("slides.txt"), encoding: .utf8) {
            var listed: [String] = []
            for line in list.components(separatedBy: "\n") {
                let f = line.trimmingCharacters(in: .whitespaces)
                if images.contains(f) && !listed.contains(f) { listed.append(f) }
            }
            images = listed + images.filter { !listed.contains($0) }
        }
        return images.isEmpty ? nil : .images(images)
    }
    func imageDeckHtml(_ name: String, _ images: [String]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let sections = images.enumerated().map { i, f in
            let src = f.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? f
            return "<section class=\"slide\(i == 0 ? " active" : "")\"><img src=\"\(src)\" alt=\"\(esc(f))\"></section>"
        }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(esc(name))</title><style>
        html,body{margin:0;height:100%;background:#000;overflow:hidden}
        section{position:fixed;inset:0;display:none}section.active{display:block}
        img{width:100%;height:100%;object-fit:contain}</style></head><body>
        \(sections)
        <script>
        const s=[...document.querySelectorAll('section')];let i=0;
        const go=n=>{s[i].classList.remove('active');i=Math.max(0,Math.min(s.length-1,n));s[i].classList.add('active')};
        addEventListener('keydown',e=>{
          if(['ArrowRight','ArrowDown','PageDown',' ','Enter'].includes(e.key))go(i+1);
          else if(['ArrowLeft','ArrowUp','PageUp','Backspace'].includes(e.key))go(i-1);
          else if(e.key==='Home')go(0);else if(e.key==='End')go(s.length-1);
        });
        </script></body></html>
        """
    }

    // ---------- notes.md (same format as the Node version) ----------

    static let notesHeader = """
    <!-- Speaker notes for Lectern. There is one section per slide, in slide order.
    Write the notes for a slide under its heading. Keep "## Slide N" at the start of each heading:
    Lectern uses the number to match notes to slides. The text after the dot is only a label.
    A note here wins over a note written inside the deck's HTML (<aside class="notes"> or data-notes).
    Lectern shows changes to this file in the presenter view within a few seconds. -->
    """
    private let headingRE = try! NSRegularExpression(pattern: "^## Slide (\\d+)\\b.*$", options: [.anchorsMatchLines])
    private let labelPrefixRE = try! NSRegularExpression(pattern: "^## Slide \\d+\\s*·?\\s*")

    /// A folder deck keeps notes in notes.md. An imported HTML file keeps them in <file name>.notes.md beside it.
    func notesPath(_ deck: String) -> URL {
        if let file = linkedFile(deck) { return file.deletingPathExtension().appendingPathExtension("notes.md") }
        return deckDir(deck)!.appendingPathComponent("notes.md")
    }

    func readNotes(_ deck: String) -> ([String: String], [String: String]) {
        guard let text = try? String(contentsOf: notesPath(deck), encoding: .utf8) else { return ([:], [:]) }
        let ns = text as NSString
        let marks = headingRE.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var notes: [String: String] = [:], labels: [String: String] = [:]
        for (i, m) in marks.enumerated() {
            let n = ns.substring(with: m.range(at: 1))
            let start = m.range.location + m.range.length
            let end = i + 1 < marks.count ? marks[i + 1].range.location : ns.length
            notes[n] = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = ns.substring(with: m.range)
            labels[n] = labelPrefixRE.stringByReplacingMatches(in: heading, range: NSRange(location: 0, length: (heading as NSString).length), withTemplate: "")
        }
        return (notes, labels)
    }

    func writeNotes(_ deck: String, _ notes: [String: String], _ labels: [String: String], _ count: Int, _ title: String) {
        let n = max(count, notes.keys.compactMap { Int($0) }.max() ?? 0, 0)
        var out = "# Speaker notes\(title.isEmpty ? "" : ": " + title)\n\n\(Self.notesHeader)\n"
        for i in stride(from: 1, through: n, by: 1) {
            let label = (labels[String(i)] ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let note = notes[String(i)] ?? ""
            out += "\n## Slide \(i)\(label.isEmpty ? "" : " · " + label)\n\n\(note.isEmpty ? "" : note + "\n")"
        }
        try? out.write(to: notesPath(deck), atomically: true, encoding: .utf8)
    }

    func readTitle(_ deck: String) -> String {
        guard let text = try? String(contentsOf: notesPath(deck), encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n") where line.hasPrefix("# Speaker notes: ") {
            return String(line.dropFirst("# Speaker notes: ".count))
        }
        return ""
    }

    // ---------- reordering slides (same as reorderDeck in bin/lectern.js) ----------

    struct Refusal: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }
    private let sectionTagRE = try! NSRegularExpression(pattern: "</?section\\b[^>]*>", options: [.caseInsensitive])
    private let commentRE = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
    private let leadRE = try! NSRegularExpression(pattern: "(?:\\s*<!--(?:(?!-->)[\\s\\S])*-->)*\\s*$")

    /// Finds each top-level <section> block (start, end) in the deck HTML.
    func slideBlocks(_ html: NSString) throws -> [(Int, Int)] {
        var blocks: [(Int, Int)] = [], depth = 0, start = -1
        for m in sectionTagRE.matches(in: html as String, range: NSRange(location: 0, length: html.length)) {
            let tag = html.substring(with: m.range)
            if !tag.hasPrefix("</") { if depth == 0 { start = m.range.location }; depth += 1 }
            else { depth -= 1; if depth == 0 { blocks.append((start, m.range.location + m.range.length)) } }
            if depth < 0 { throw Refusal("The deck HTML has an extra </section>.") }
        }
        if depth != 0 { throw Refusal("The deck HTML has a <section> that is not closed.") }
        return blocks
    }

    func reorderDeck(_ deck: String, _ order: [Int]) throws {
        guard let entry = deckEntry(deck), let dir = deckDir(deck) else { throw Refusal("No slides found.") }
        let n = order.count
        if Set(order).count != n || order.contains(where: { $0 < 0 || $0 >= n }) { throw Refusal("The new order must use each slide once.") }
        switch entry {
        case .images(let images):
            if n != images.count { throw Refusal("The deck has \(images.count) slides, not \(n).") }
            try (order.map { images[$0] }.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("slides.txt"), atomically: true, encoding: .utf8)
        case .html(let name):
            let file = dir.appendingPathComponent(name)
            let data = try Data(contentsOf: file)
            guard let str = String(data: data, encoding: .utf8) else { throw Refusal("The deck HTML is not UTF-8 text.") }
            let html = str as NSString
            let blocks = try slideBlocks(html)
            if blocks.count != n { throw Refusal("Lectern found \(blocks.count) slide blocks in the HTML but the deck shows \(n) slides, so it did not change anything.") }
            // Each piece = the spaces and comments before a slide + the slide itself.
            var pieceStarts: [Int] = []
            for (i, (a, _)) in blocks.enumerated() {
                var from = i > 0 ? blocks[i - 1].1 : a
                if i == 0, let lead = leadRE.firstMatch(in: html.substring(to: a), range: NSRange(location: 0, length: a)) {
                    from = a - lead.range.length
                }
                let between = html.substring(with: NSRange(location: from, length: a - from))
                let stripped = commentRE.stringByReplacingMatches(in: between, range: NSRange(location: 0, length: (between as NSString).length), withTemplate: "")
                if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw Refusal("There is other content between slides, so Lectern did not change anything.")
                }
                pieceStarts.append(from)
            }
            let pieces = blocks.enumerated().map { i, b in html.substring(with: NSRange(location: pieceStarts[i], length: b.1 - pieceStarts[i])) }
            let head = html.substring(to: pieceStarts[0]), tail = html.substring(from: blocks[n - 1].1)
            // Keep a copy of the old file, just in case.
            let backup = dir.appendingPathComponent(".lectern-backup")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            try data.write(to: backup.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(name)"))
            try Data((head + order.map { pieces[$0] }.joined() + tail).utf8).write(to: file)
        }
        // Notes follow their slides.
        if FileManager.default.fileExists(atPath: notesPath(deck).path) {
            let (notes, labels) = readNotes(deck)
            var nn: [String: String] = [:], nl: [String: String] = [:]
            for (i, old) in order.enumerated() {
                if let v = notes[String(old + 1)], !v.isEmpty { nn[String(i + 1)] = v }
                if let v = labels[String(old + 1)], !v.isEmpty { nl[String(i + 1)] = v }
            }
            writeNotes(deck, nn, nl, n, readTitle(deck))
        }
    }

    /// Changes when someone (or an agent) edits the deck or its notes, so open windows can refresh.
    func deckVersion(_ deck: String) -> [String: Double] {
        let dir = deckDir(deck)!, own = notesPath(deck).standardizedFileURL.path
        var slides = 0.0, notes = 0.0
        func walk(_ d: URL, _ depth: Int) {
            let items = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
            for f in items {
                let name = f.lastPathComponent
                if name.hasPrefix(".") || name == "node_modules" { continue }
                let rv = try? f.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                if rv?.isDirectory == true { if depth < 2 { walk(f, depth + 1) }; continue }
                let t = (rv?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
                if f.standardizedFileURL.path == own { notes = max(notes, t) }
                else if name == "notes.md" || name.hasSuffix(".notes.md") { continue } // another deck's notes
                else { slides = max(slides, t) }
            }
        }
        walk(dir, 0)
        return ["slides": slides, "notes": notes]
    }

    // ---------- files ----------

    static let types: [String: String] = [
        "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8", "css": "text/css", "js": "text/javascript",
        "mjs": "text/javascript", "json": "application/json", "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg",
        "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif", "ico": "image/x-icon",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf", "mp4": "video/mp4",
        "webm": "video/webm", "mp3": "audio/mpeg", "wav": "audio/wav", "m4a": "audio/mp4", "pdf": "application/pdf",
        "md": "text/markdown; charset=utf-8",
    ]
    static let adapterTag = "<script src=\"/_lectern/adapter.js\"></script>"
    private let headRE = try! NSRegularExpression(pattern: "<head[^>]*>", options: [.caseInsensitive])

    /// Adds the Lectern adapter to a deck page, before the deck's own scripts.
    func injectAdapter(_ html: String) -> String {
        let ns = html as NSString
        if let m = headRE.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            return ns.replacingCharacters(in: NSRange(location: m.range.location + m.range.length, length: 0), with: Self.adapterTag)
        }
        return Self.adapterTag + html
    }

    /// Joins a path onto a folder, and refuses anything that tries to leave the folder.
    func inside(_ dir: URL, _ rel: String) -> URL? {
        let base = dir.standardizedFileURL.path
        let target = dir.appendingPathComponent(rel).standardizedFileURL
        return target.path == base || target.path.hasPrefix(base + "/") ? target : nil
    }

    func file(_ url: URL, inject: Bool = false) -> Response {
        guard let data = try? Data(contentsOf: url) else { return .text(404, "Not found") }
        let type = Self.types[url.pathExtension.lowercased()] ?? "application/octet-stream"
        if inject && type.hasPrefix("text/html"), let html = String(data: data, encoding: .utf8) {
            return Response(status: 200, type: type, body: Data(injectAdapter(html).utf8))
        }
        return Response(status: 200, type: type, body: data)
    }
}

// ---------- HTTP plumbing ----------

struct Request {
    let method: String
    let path: String
    let body: Data

    /// Returns a request once all of it (headers and body) has arrived, else nil.
    static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased() == "content-length" { length = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0 }
        }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }
        let target = String(first[1])
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        return Request(method: String(first[0]), path: path.isEmpty ? "/" : path, body: data[bodyStart..<(bodyStart + length)])
    }
}

struct Response {
    let status: Int
    let type: String
    let body: Data

    static func text(_ status: Int, _ s: String) -> Response { Response(status: status, type: "text/plain; charset=utf-8", body: Data(s.utf8)) }
    static func json(_ obj: Any) -> Response {
        Response(status: 200, type: "application/json", body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8))
    }

    func bytes() -> Data {
        let reasons = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 500: "Internal Server Error"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\n"
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }
}
