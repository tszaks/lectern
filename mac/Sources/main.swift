// Lectern for Mac: a small native app that shows the Lectern pages in two windows.
// One click on "Start presenting" puts the presenter view full screen on the Mac's own
// screen and the slides full screen on the TV or projector. No dragging windows.
import AppKit
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate, WKScriptMessageHandler, NSMenuDelegate {
    var server: Server!
    var base = ""
    var mainWindow: NSWindow!
    var mainView: WKWebView!
    var audienceWindow: NSWindow?
    var audienceView: WKWebView?
    let focus = Focus()
    let env = ProcessInfo.processInfo.environment
    var pendingOpen: [URL] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        // Remember each mouse press, so a drag on the page's top bar can move the window.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in self.lastMouseDown = e; return e }
        let library = env["LECTERN_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Lectern")
        server = Server(library: library, appDir: Bundle.main.resourceURL!.appendingPathComponent("app"))
        do {
            try server.start { port in
                self.base = "http://127.0.0.1:\(port)"
                print("Lectern is running at \(self.base)/"); fflush(stdout)
                self.openMainWindow()
                self.pendingOpen.forEach { self.openAny($0) }
                self.pendingOpen = []
                if let deck = self.env["LECTERN_SELFTEST"] { SelfTest(app: self, deck: deck).run() }
                if self.env["LECTERN_HITTEST"] != nil { self.reportClickTargets() }
                if let deck = self.env["LECTERN_PACKTEST"] { self.packTest(deck) }
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            self.placeWindows() // a TV was plugged in or unplugged
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { focus.end(wait: true) }

    // A .lectern file, a folder or an HTML file: double-clicked, dropped on the app icon, or opened with the app.
    func application(_ sender: NSApplication, open urls: [URL]) {
        if base.isEmpty { pendingOpen += urls } else { urls.forEach { openAny($0) } }
    }
    func openAny(_ url: URL) {
        if url.pathExtension.lowercased() == "lectern" { importProject(url) } else { addDeck(url) }
    }

    // ---------- .lectern files: a whole project in one file, to send to someone ----------
    // A .lectern file is a zip of the project folder: the deck, its images and fonts, and notes.md.

    static let projectType = UTType(exportedAs: "com.szakacsmedia.lectern.project", conformingTo: .zip)

    /// Unpacks a .lectern file into a new project and opens it.
    func importProject(_ file: URL) {
        let fm = FileManager.default
        let base = file.deletingPathExtension().lastPathComponent
        var name = base, n = 2
        while fm.fileExists(atPath: server.library.appendingPathComponent(name).path) { name = "\(base) \(n)"; n += 1 }
        let dest = server.library.appendingPathComponent(name)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", file.path, dest.path])
            // A zip made by hand may wrap everything in one folder: unwrap it.
            let items = try fm.contentsOfDirectory(atPath: dest.path).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
            var isDir: ObjCBool = false
            if items.count == 1, fm.fileExists(atPath: dest.appendingPathComponent(items[0]).path, isDirectory: &isDir), isDir.boolValue {
                let inner = dest.appendingPathComponent(items[0])
                for f in try fm.contentsOfDirectory(atPath: inner.path) { try fm.moveItem(at: inner.appendingPathComponent(f), to: dest.appendingPathComponent(f)) }
                try fm.removeItem(at: inner)
            }
            try? fm.removeItem(at: dest.appendingPathComponent("__MACOSX"))
        } catch {
            try? fm.removeItem(at: dest)
            let a = NSAlert(); a.messageText = "Lectern could not open “\(file.lastPathComponent)”."; a.informativeText = error.localizedDescription; a.runModal()
            return
        }
        mainView.load(URLRequest(url: presentURL(name)))
        mainWindow.makeKeyAndOrderFront(nil)
    }

    /// Saves the open project as one .lectern file.
    @objc func exportProject(_ sender: Any?) {
        guard let url = mainView.url, url.path.hasPrefix("/present/"),
              let name = url.path.dropFirst("/present/".count).removingPercentEncoding, !name.isEmpty,
              let dir = server.deckDir(name) else {
            let a = NSAlert(); a.messageText = "Open a project first, then choose Export."; a.runModal(); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = name + ".lectern"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Save the whole project (slides, images and notes) as one file you can send."
        panel.beginSheetModal(for: mainWindow) { r in
            guard r == .OK, let out = panel.url else { return }
            do {
                try self.writeProject(from: dir, linkedFile: self.server.linkedFile(name), to: out)
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                let a = NSAlert(); a.messageText = "Lectern could not export the project."; a.informativeText = error.localizedDescription; a.runModal()
            }
        }
    }
    func writeProject(from dir: URL, linkedFile: URL?, to out: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("lectern-export-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Copy the project without hidden files (for example .git) and build folders.
        try run("/usr/bin/rsync", ["-a", "--exclude", ".*", "--exclude", "node_modules", dir.resolvingSymlinksInPath().path + "/", tmp.path + "/"])
        // A project that is one linked HTML file: name it index.html, and its notes notes.md, so it opens as a normal project.
        if let file = linkedFile, file.lastPathComponent != "index.html" {
            let stem = file.deletingPathExtension().lastPathComponent
            try? fm.removeItem(at: tmp.appendingPathComponent("index.html"))
            try fm.moveItem(at: tmp.appendingPathComponent(file.lastPathComponent), to: tmp.appendingPathComponent("index.html"))
            let notes = tmp.appendingPathComponent(stem + ".notes.md")
            if fm.fileExists(atPath: notes.path) {
                try? fm.removeItem(at: tmp.appendingPathComponent("notes.md"))
                try fm.moveItem(at: notes, to: tmp.appendingPathComponent("notes.md"))
            }
        }
        try? fm.removeItem(at: out)
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", tmp.path, out.path])
    }
    /// Test aid: export a project to a .lectern file, open that file as a new project, and report both.
    func packTest(_ deck: String) {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(deck).lectern")
        do {
            try writeProject(from: server.deckDir(deck)!, linkedFile: server.linkedFile(deck), to: out)
            let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("PACK exported \(out.lastPathComponent): \(size) bytes")
            importProject(out)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("PACK opened as: \(self.mainView.url?.path.removingPercentEncoding ?? "?")"); fflush(stdout)
                NSApp.terminate(nil)
            }
        } catch { print("PACK failed: \(error.localizedDescription)"); fflush(stdout); NSApp.terminate(nil) }
    }

    @discardableResult
    func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Lectern", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "\(tool) failed" : msg])
        }
        return p.terminationStatus
    }

    // ---------- windows ----------

    func makeConfig() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        // Both windows share one web "profile", so the presenter and the slides can talk to each other.
        c.websiteDataStore = .default()
        c.preferences.javaScriptCanOpenWindowsAutomatically = true
        c.mediaTypesRequiringUserActionForPlayback = []
        // "Full screen" in Start presenting uses the web page's own full screen.
        if #available(macOS 12.3, *) { c.preferences.isElementFullscreenEnabled = true }
        // Tell the pages they are inside the Mac app, so they leave room for the window buttons
        // and let an empty part of the top bar move the window.
        c.userContentController.add(self, name: "lecternWindow")
        let js = """
        document.documentElement.classList.add('mac-app');
        addEventListener('mousedown', e => {
          if (e.button !== 0 || e.target.closest('button, a, input, textarea, select, iframe, [contenteditable], .no-drag')) return;
          if (e.clientY > \(Self.barHeight)) return;
          window.webkit.messageHandlers.lecternWindow.postMessage(e.detail === 2 ? 'zoom' : 'drag');
        }, true);
        """
        c.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return c
    }

    func makeWindow(_ view: WKWebView, title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        // No separate title bar: the page runs to the top, and the window buttons sit in the page's own top bar.
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentView = view
        w.collectionBehavior = [.fullScreenPrimary]
        w.backgroundColor = NSColor(red: 0.067, green: 0.075, blue: 0.071, alpha: 1)
        w.isReleasedWhenClosed = false
        w.delegate = self
        view.uiDelegate = self
        view.navigationDelegate = self
        if #available(macOS 13.3, *) { view.isInspectable = true }
        return w
    }

    func openMainWindow() {
        let config = makeConfig()
        // The home page can ask the app to add a folder (as a link, so nothing is copied).
        config.userContentController.add(self, name: "lectern")
        mainView = WKWebView(frame: .zero, configuration: config)
        mainWindow = makeWindow(mainView, title: "Lectern", size: NSSize(width: 1280, height: 800))
        mainWindow.setFrameAutosaveName("LecternMain")
        if mainWindow.frame.origin == .zero { mainWindow.center() }
        mainWindow.makeKeyAndOrderFront(nil)
        // Open the deck that was open last time, if it is still in the library.
        if env["LECTERN_SELFTEST"] == nil, let last = UserDefaults.standard.string(forKey: "lastDeck"), deckExists(last) {
            mainView.load(URLRequest(url: presentURL(last)))
        } else {
            mainView.load(URLRequest(url: URL(string: base + "/")!))
        }
    }

    // ---------- remembering decks ----------

    func deckExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: server.library.appendingPathComponent(name).path)
    }
    func presentURL(_ name: String) -> URL {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? name
        return URL(string: base + "/present/" + enc)!
    }
    var recentDecks: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentDecks") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: "recentDecks") }
    }
    /// Each time a deck opens in the presenter, remember it (last opened, and the recent list).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === mainView, let url = webView.url, url.path.hasPrefix("/present/") else { return }
        let name = url.path.dropFirst("/present/".count).removingPercentEncoding ?? ""
        guard !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: "lastDeck")
        recentDecks = [name] + recentDecks.filter { $0 != name }
    }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "addDeck": openDeck(nil)
        case "exportProject": exportProject(nil)
        case "drag", "zoom": windowAction(message.body as! String, from: message.webView)
        case "endPresenting":
            // The presenter pressed End or Esc: close the slides and leave full screen.
            audienceWindow?.close()
            if let mw = mainWindow, mw.styleMask.contains(.fullScreen) { mw.toggleFullScreen(nil) }
            focus.end()
            stayAwake(false)
        case "presentingStart": stayAwake(true)   // Full screen mode (no slides window)
        case "presentingEnd": if audienceWindow == nil { stayAwake(false) }
        default: break
        }
    }
    // File > Open Recent is filled in each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let names = recentDecks.filter(deckExists)
        if names.isEmpty { menu.addItem(NSMenuItem(title: "No recent decks", action: nil, keyEquivalent: "")) }
        for name in names {
            let i = NSMenuItem(title: name, action: #selector(openRecent(_:)), keyEquivalent: "")
            i.representedObject = name
            menu.addItem(i)
        }
    }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        mainView.load(URLRequest(url: presentURL(name)))
        mainWindow.makeKeyAndOrderFront(nil)
    }

    // The presenter page asks for the slides window (its "Start presenting" button).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        let isAudience = url.path.hasPrefix("/audience/") || url.path.hasSuffix("audience.html")
        guard isAudience, url.host == "127.0.0.1" else {
            NSWorkspace.shared.open(url) // other links open in the normal browser
            return nil
        }
        if let w = audienceWindow, w.isVisible {
            placeWindows()
            return nil
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        let w = makeWindow(view, title: "Lectern · Slides", size: NSSize(width: 1280, height: 720))
        audienceView = view
        audienceWindow = w
        w.makeKeyAndOrderFront(nil)
        placeWindows()
        stayAwake(true)
        // Turn on Do Not Disturb only if it was set up beforehand (Lectern menu). Never ask here:
        // a question at this moment would pop up as the talk starts and freeze the windows until answered.
        if env["LECTERN_SELFTEST"] == nil { focus.begin(missing: {}) }
        return view // WebKit loads the slides page into it
    }

    /// Presenter full screen on the Mac's own screen; slides full screen on the other screen.
    func placeWindows() {
        guard let aw = audienceWindow, aw.isVisible else { return }
        let builtIn = NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 }
        let mac = builtIn ?? NSScreen.main
        let tv = NSScreen.screens.first { $0 != mac }
        if let tv = tv {
            if aw.styleMask.contains(.fullScreen) && aw.screen != tv { aw.toggleFullScreen(nil) }
            aw.setFrame(tv.frame, display: true)
            if !aw.styleMask.contains(.fullScreen) { aw.toggleFullScreen(nil) }
            if let mac = mac, let mw = mainWindow {
                if mw.screen != mac && !mw.styleMask.contains(.fullScreen) { mw.setFrame(mac.visibleFrame, display: true) }
                // One full-screen change at a time looks smoother on older Macs.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !mw.styleMask.contains(.fullScreen) { mw.toggleFullScreen(nil) }
                    self.focusPresenter()
                }
            }
        } else {
            // Only one screen: the slides open in a normal window, in front, so you can see it opened.
            // (Bringing the presenter back to the front here hid it, and "Start presenting" looked broken.)
            aw.setContentSize(NSSize(width: 1280, height: 720))
            aw.center()
            aw.makeKeyAndOrderFront(nil)
            return
        }
        focusPresenter()
    }

    /// Keys from the keyboard or a USB clicker go to the presenter window.
    func focusPresenter() {
        guard let mw = mainWindow else { return }
        mw.makeKeyAndOrderFront(nil)
        mw.makeFirstResponder(mainView)
    }

    // ---------- window buttons inside the page's top bar ----------

    /// Height of the page's top bar. The red, yellow and green buttons are centred in it.
    static let barHeight: CGFloat = 60

    /// Moves the window buttons down so they line up with the page's top bar (AppKit puts them at the very top).
    func placeTrafficLights(_ w: NSWindow) {
        guard !w.styleMask.contains(.fullScreen),
              let close = w.standardWindowButton(.closeButton),
              let container = close.superview?.superview else { return }
        let h = Self.barHeight
        // Only as wide as the three buttons, so it never sits over the page's own controls.
        var f = container.frame
        f.size.height = h
        f.size.width = 86
        f.origin.x = 0
        f.origin.y = w.frame.height - h
        container.frame = f
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, kind) in kinds.enumerated() {
            guard let b = w.standardWindowButton(kind) else { continue }
            b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 20, y: (h - b.frame.height) / 2))
        }
    }
    /// Test aid: says which view would receive a click at points across the top bar (no real clicks).
    func reportClickTargets() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let w = self.mainWindow, let frame = w.contentView?.superview else { return }
            let width = w.frame.width, height = w.frame.height
            for (name, x) in [("window buttons", 30.0), ("title", 200.0), ("timer", width / 2), ("start presenting", width - 90)] {
                let p = NSPoint(x: x, y: height - 30)
                var v = frame.hitTest(p), chain: [String] = []
                while let cur = v { chain.append(String(describing: type(of: cur))); v = cur.superview }
                let toPage = chain.contains("WKWebView")
                print("HIT \(name): \(toPage ? "page gets the click" : "BLOCKED by " + (chain.first ?? "nothing"))")
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    func windowDidResize(_ n: Notification) { if let w = n.object as? NSWindow { placeTrafficLights(w) } }
    func windowDidExitFullScreen(_ n: Notification) { if let w = n.object as? NSWindow { placeTrafficLights(w) } }
    func windowDidBecomeKey(_ n: Notification) { if let w = n.object as? NSWindow { placeTrafficLights(w) } }

    /// The page asks to move the window (a drag on an empty part of its top bar) or to zoom it (a double-click).
    var lastMouseDown: NSEvent?
    func windowAction(_ what: String, from view: WKWebView?) {
        guard let w = view?.window else { return }
        if what == "zoom" { w.zoom(nil); return }
        if what == "drag", let e = lastMouseDown, e.window === w, ProcessInfo.processInfo.systemUptime - e.timestamp < 1 {
            w.performDrag(with: e)
        }
    }

    func windowWillClose(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        if w === audienceWindow {
            audienceWindow = nil
            audienceView = nil
            focus.end()
            stayAwake(false)
        } else if w === mainWindow {
            NSApp.terminate(nil)
        }
    }

    // ---------- keep the Mac awake while presenting ----------
    // Without this the display can go dark during a long video or discussion (no key is pressed then).
    var awakeToken: NSObjectProtocol?
    func stayAwake(_ on: Bool) {
        if on, awakeToken == nil {
            awakeToken = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated], reason: "Presenting slides")
        } else if !on, let t = awakeToken {
            ProcessInfo.processInfo.endActivity(t); awakeToken = nil
        }
    }

    // ---------- Do Not Disturb setup (one time) ----------

    func offerFocusSetup() {
        if UserDefaults.standard.bool(forKey: "focusSetupOffered") { return }
        UserDefaults.standard.set(true, forKey: "focusSetupOffered")
        let a = NSAlert()
        a.messageText = "Turn on Do Not Disturb while you present?"
        a.informativeText = "This is a one-time step. Click Set Up. The Shortcuts app opens two small shortcuts. Click \"Add Shortcut\" for each one. After that, Lectern turns Do Not Disturb on when you start and off when you stop."
        a.addButton(withTitle: "Set Up")
        a.addButton(withTitle: "Not Now")
        if a.runModal() == .alertFirstButtonReturn { focus.setUp() }
    }

    @objc func setUpFocus(_ sender: Any?) { focus.setUp() }

    // ---------- adding a deck folder ----------

    @objc func openDeck(_ sender: Any?) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.html, .folder, Self.projectType]
        p.prompt = "Import"
        p.message = "Choose a Lectern project file, an HTML file, or a folder with an HTML deck or slide images."
        if p.runModal() == .OK, let url = p.url { openAny(url) }
    }

    /// Adds a folder or one HTML file to the library as a link (nothing is copied),
    /// so edits to the original show up live, and it stays in the list next time.
    func addDeck(_ folder: URL) {
        let fm = FileManager.default
        let lib = server.library.standardizedFileURL, folder = folder.standardizedFileURL
        let isFile = ["html", "htm"].contains(folder.pathExtension.lowercased())
        var name = isFile ? folder.deletingPathExtension().lastPathComponent : folder.lastPathComponent
        if folder.deletingLastPathComponent().path != lib.path {
            // Reuse a link that already points to this folder, or make one with a free name.
            var n = 1
            while true {
                let link = lib.appendingPathComponent(name)
                let dest = try? fm.destinationOfSymbolicLink(atPath: link.path)
                if let dest = dest, URL(fileURLWithPath: dest).standardizedFileURL.path == folder.path { break }
                if dest == nil && !fm.fileExists(atPath: link.path) {
                    try? fm.createSymbolicLink(at: link, withDestinationURL: folder)
                    break
                }
                n += 1
                name = "\(isFile ? folder.deletingPathExtension().lastPathComponent : folder.lastPathComponent) \(n)"
            }
        }
        mainView.load(URLRequest(url: presentURL(name)))
        mainWindow.makeKeyAndOrderFront(nil)
    }

    // The slides page closed itself (window.close()), for example after End.
    func webViewDidClose(_ webView: WKWebView) {
        if webView === audienceView { audienceWindow?.close() }
    }

    // ---------- pages asking for files, alerts, and questions ----------

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = parameters.allowsDirectories
        p.canChooseFiles = !parameters.allowsDirectories
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.begin { r in completionHandler(r == .OK ? p.urls : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.runModal(); completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        completionHandler(a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // Links to other websites open in the normal browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.targetFrame?.isMainFrame == true,
           action.navigationType == .linkActivated, url.host != "127.0.0.1" {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    // ---------- menu ----------

    func buildMenu() {
        let bar = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(); let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            top.submenu = m; bar.addItem(top)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; return i
        }
        menu("Lectern", [item("About Lectern", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
                         .separator(),
                         item("Set Up Do Not Disturb…", #selector(setUpFocus(_:)), ""),
                         .separator(),
                         item("Hide Lectern", #selector(NSApplication.hide(_:)), "h"),
                         item("Quit Lectern", #selector(NSApplication.terminate(_:)), "q")])
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent"); recentMenu.delegate = self
        recent.submenu = recentMenu
        menu("File", [item("New Project", #selector(newProject(_:)), "n"),
                      item("Import…", #selector(openDeck(_:)), "i"),
                      item("Open…", #selector(openDeck(_:)), "o"),
                      item("Export Project…", #selector(exportProject(_:)), "e"),
                      recent,
                      item("All Projects", #selector(goHome(_:)), "l", [.command, .shift]),
                      .separator(),
                      item("Close Window", #selector(NSWindow.performClose(_:)), "w")])
        menu("Edit", [item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]),
                      .separator(),
                      item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
                      item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a")])
        menu("View", [item("Reload", #selector(reload(_:)), "r"),
                      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])])
        menu("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = bar
    }

    @objc func newProject(_ s: Any?) { mainView.load(URLRequest(url: URL(string: base + "/?new=1")!)); mainWindow.makeKeyAndOrderFront(nil) }
    @objc func goHome(_ s: Any?) { mainView.load(URLRequest(url: URL(string: base + "/")!)) }
    @objc func reload(_ s: Any?) { (NSApp.keyWindow?.contentView as? WKWebView)?.reload() }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
