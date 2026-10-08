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
        let library = env["LECTERN_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Lectern")
        server = Server(library: library, appDir: Bundle.main.resourceURL!.appendingPathComponent("app"))
        do {
            try server.start { port in
                self.base = "http://127.0.0.1:\(port)"
                print("Lectern is running at \(self.base)/"); fflush(stdout)
                self.openMainWindow()
                self.pendingOpen.forEach { self.addDeck($0) }
                self.pendingOpen = []
                if let deck = self.env["LECTERN_SELFTEST"] { SelfTest(app: self, deck: deck).run() }
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

    // A folder dropped on the app icon, or opened with the app.
    func application(_ sender: NSApplication, open urls: [URL]) {
        if base.isEmpty { pendingOpen += urls } else { urls.forEach { addDeck($0) } }
    }

    // ---------- windows ----------

    func makeConfig() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        // Both windows share one web "profile", so the presenter and the slides can talk to each other.
        c.websiteDataStore = .default()
        c.preferences.javaScriptCanOpenWindowsAutomatically = true
        c.mediaTypesRequiringUserActionForPlayback = []
        return c
    }

    func makeWindow(_ view: WKWebView, title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
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
        if message.body as? String == "addDeck" { openDeck(nil) }
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
        if env["LECTERN_SELFTEST"] == nil {
            focus.begin(missing: { self.offerFocusSetup() })
        }
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
            // Only one screen: the slides open in a normal window.
            aw.setContentSize(NSSize(width: 1280, height: 720))
            aw.center()
        }
        focusPresenter()
    }

    /// Keys from the keyboard or a USB clicker go to the presenter window.
    func focusPresenter() {
        guard let mw = mainWindow else { return }
        mw.makeKeyAndOrderFront(nil)
        mw.makeFirstResponder(mainView)
    }

    func windowWillClose(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        if w === audienceWindow {
            audienceWindow = nil
            audienceView = nil
            focus.end()
        } else if w === mainWindow {
            NSApp.terminate(nil)
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
        p.allowedContentTypes = [.html, .folder]
        p.prompt = "Import"
        p.message = "Choose an HTML file, or a folder with an HTML deck or slide images."
        if p.runModal() == .OK, let url = p.url { addDeck(url) }
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
        menu("File", [item("Import…", #selector(openDeck(_:)), "i"),
                      item("Open…", #selector(openDeck(_:)), "o"),
                      recent,
                      item("All Decks", #selector(goHome(_:)), "l", [.command, .shift]),
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
