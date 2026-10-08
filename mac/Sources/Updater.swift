import AppKit

/// Updates Lectern from its GitHub releases.
/// When Lectern opens (never during a show) it asks GitHub for the newest version. If that is newer,
/// it asks the person; on "Update" it downloads the zip, checks that the app inside is signed by the
/// same developer as this one, puts it in place of this app, and opens it again.
final class Updater {
    static let latestAPI = URL(string: "https://api.github.com/repos/tszaks/lectern/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/tszaks/lectern/releases/latest")!

    let showRunning: () -> Bool
    /// LECTERN_UPDATETEST: answer "Update" by itself and print what happens (for tests).
    let auto = ProcessInfo.processInfo.environment["LECTERN_UPDATETEST"] != nil
    init(showRunning: @escaping () -> Bool) { self.showRunning = showRunning }

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// "0.2.10" is newer than "0.2.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// `quiet`: at launch, say nothing when there is no update or no internet.
    func check(quiet: Bool) {
        var req = URLRequest(url: Self.latestAPI, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let zip = (json?["assets"] as? [[String: Any]])?
                .first { ($0["name"] as? String) == "Lectern.zip" }?["browser_download_url"] as? String
            DispatchQueue.main.async {
                guard !tag.isEmpty, let zip = zip, let url = URL(string: zip) else {
                    if !quiet { self.tell("Could not check for updates", "Check that this Mac is online, then try again.") }
                    return
                }
                guard Self.isNewer(tag, than: self.current) else {
                    if !quiet { self.tell("Lectern is up to date", "You have the newest version, \(self.current).") }
                    return
                }
                if self.showRunning() { return } // never interrupt a talk
                if self.auto { print("UPDATE found \(tag)"); fflush(stdout); return self.install(from: url) }
                let a = NSAlert()
                a.messageText = "Lectern \(tag) is available"
                a.informativeText = "You have \(self.current). Update now? It takes about a minute, and Lectern opens again by itself."
                a.addButton(withTitle: "Update")
                a.addButton(withTitle: "Later")
                if a.runModal() == .alertFirstButtonReturn { self.install(from: url) }
            }
        }.resume()
    }

    func install(from url: URL) {
        let progress = NSAlert()
        progress.messageText = "Updating Lectern…"
        progress.informativeText = "Downloading the new version."
        progress.addButton(withTitle: "Cancel")
        var cancelled = false
        let task = URLSession.shared.downloadTask(with: url) { file, _, error in
            // Move the download before this handler returns (the system deletes it after).
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("lectern-update-\(UUID().uuidString)")
            var zip: URL?
            if let file = file {
                try? fm.createDirectory(at: work, withIntermediateDirectories: true)
                let z = work.appendingPathComponent("Lectern.zip")
                if (try? fm.moveItem(at: file, to: z)) != nil { zip = z }
            }
            DispatchQueue.main.async {
                if NSApp.modalWindow != nil { NSApp.abortModal() }
                if cancelled { return }
                guard let zip = zip, error == nil else { return self.failed("The download did not finish.") }
                self.replaceApp(zip: zip, work: work)
            }
        }
        task.resume()
        if auto { return }
        if progress.runModal() == .alertFirstButtonReturn { cancelled = true; task.cancel() }
    }

    func replaceApp(zip: URL, work: URL) {
        let fm = FileManager.default
        let unpacked = work.appendingPathComponent("unpacked")
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { return failed("The download could not be opened.") }
        let newApp = unpacked.appendingPathComponent("Lectern.app")
        // Only an app signed by the same developer as this one may replace it.
        guard fm.fileExists(atPath: newApp.path),
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0,
              let mine = teamID(Bundle.main.bundleURL), let theirs = teamID(newApp), mine == theirs else {
            return failed("The download is not signed correctly, so Lectern did not install it.")
        }
        let here = Bundle.main.bundleURL
        do {
            _ = try fm.replaceItemAt(here, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            return failed("Lectern could not replace itself (\(error.localizedDescription)).")
        }
        // Open the new copy once this one has quit.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", here.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// The developer team that signed an app, for example "3D2B7RVUXV". Nil if it is not signed by a team.
    func teamID(_ app: URL) -> String? {
        let pipe = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", app.path]
        p.standardError = pipe   // codesign -dv writes to stderr
        p.standardOutput = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let line = out.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
        let id = line.map { String($0.dropFirst("TeamIdentifier=".count)) }
        return (id == nil || id == "not set") ? nil : id
    }

    @discardableResult
    func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    func failed(_ why: String) {
        if auto { print("UPDATE failed: \(why)"); fflush(stdout); NSApp.terminate(nil); return }
        let a = NSAlert()
        a.messageText = "Lectern was not updated"
        a.informativeText = why + " You can download the new version from the Lectern page instead."
        a.addButton(withTitle: "Open Download Page")
        a.addButton(withTitle: "Close")
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasesPage) }
    }

    func tell(_ title: String, _ text: String) {
        if auto { print("UPDATE \(title)"); fflush(stdout); NSApp.terminate(nil); return }
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
