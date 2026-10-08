// A self-check used only when building and testing Lectern (LECTERN_SELFTEST=<deck name>).
// It clicks "Start presenting", presses real keys like a USB clicker, types a note,
// then writes what it saw to LECTERN_SELFTEST_OUT/results.json with pictures of both windows.
import AppKit
import WebKit

final class SelfTest {
    let app: AppDelegate
    let deck: String
    let out: URL
    var results: [String: Any] = [:]

    init(app: AppDelegate, deck: String) {
        self.app = app
        self.deck = deck
        out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LECTERN_SELFTEST_OUT"] ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

    func js(_ view: WKWebView?, _ code: String, _ done: @escaping (Any?) -> Void) {
        guard let view = view else { return done(nil) }
        view.evaluateJavaScript(code) { v, e in
            if let s = v as? String, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) { done(o) }
            else { done(v ?? "error: \(e?.localizedDescription ?? "nil")") }
        }
    }

    /// A real key press, sent the way the keyboard (or a clicker) sends it.
    func press(_ chars: String, _ code: UInt16, function: Bool = false) {
        let w = app.mainWindow!
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: function ? [.function] : [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                        context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) {
                w.sendEvent(e)
            }
        }
    }
    func pageDown() { press("\u{F72D}", 121, function: true) }

    static let presenterState = """
    JSON.stringify((() => {
      const d = document.getElementById('current').contentDocument;
      const slides = [...d.querySelectorAll('section.slide')];
      return { count: document.getElementById('count').textContent, status: document.getElementById('status').textContent,
               index: slides.findIndex(s => s.classList.contains('active')), steps: d.querySelectorAll('.step.shown').length,
               notes: document.getElementById('notes').value, black: document.body.classList.contains('black') };
    })())
    """
    static let audienceState = """
    JSON.stringify((() => {
      const d = document.getElementById('deck').contentDocument;
      const slides = [...d.querySelectorAll('section.slide')];
      return { index: slides.findIndex(s => s.classList.contains('active')), steps: d.querySelectorAll('.step.shown').length,
               black: document.getElementById('black').classList.contains('on'), width: innerWidth, height: innerHeight };
    })())
    """

    func snap(_ view: WKWebView?, _ name: String, _ done: @escaping () -> Void) {
        guard let view = view else { return done() }
        view.takeSnapshot(with: nil) { img, _ in
            if let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: self.out.appendingPathComponent(name + ".png"))
            }
            done()
        }
    }

    /// A real mouse event in the presenter window, at a point given in page (CSS) pixels.
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) {
        let w = app.mainWindow!
        let h = w.contentView!.bounds.height
        if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: h - y), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                      context: nil, eventNumber: Int.random(in: 1...100000), clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
            switch type {
            case .leftMouseDown: app.mainView.mouseDown(with: e)
            case .leftMouseDragged: app.mainView.mouseDragged(with: e)
            default: app.mainView.mouseUp(with: e)
            }
        }
    }

    /// Strip test: drag slide 2 to after slide 3 with the mouse, then click Save order.
    func runStrip() {
        let enc = deck.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? deck
        app.mainView.load(URLRequest(url: URL(string: app.base + "/present/" + enc)!))
        let thumbs = """
        JSON.stringify((() => {
          const f = document.getElementById('stripframe'), r = f.getBoundingClientRect();
          const t = [...f.contentDocument.querySelectorAll('.lectern-thumb')].slice(0, 4).map(c => {
            const b = c.getBoundingClientRect(); return { x: r.left + b.left + b.width / 2, y: r.top + b.top + b.height / 2, w: b.width, old: +c.dataset.old }; });
          return { thumbs: t, changed: document.getElementById('strip').classList.contains('changed'),
                   order: [...f.contentDocument.querySelectorAll('.lectern-thumb')].slice(0, 5).map(c => +c.dataset.old) };
        })())
        """
        after(5) {
            NSApp.activate(ignoringOtherApps: true)
            self.app.mainWindow.makeKeyAndOrderFront(nil)
            self.js(self.app.mainView, "'strip is always open'") { _ in }
            self.after(4) {
                self.js(self.app.mainView, thumbs) { v in
                    print("strip before:", v ?? "nil"); fflush(stdout)
                    self.results["strip_before"] = v
                    guard let d = v as? [String: Any], let t = d["thumbs"] as? [[String: Any]], t.count >= 3,
                          let x1 = t[1]["x"] as? Double, let y1 = t[1]["y"] as? Double,
                          let x2 = t[2]["x"] as? Double, let w2 = t[2]["w"] as? Double else { return self.finishStrip() }
                    let target = x2 + w2 * 0.35 // right half of slide 3
                    self.results["strip_windowContentHeight"] = self.app.mainWindow.contentView!.bounds.height
                    self.js(self.app.mainView, """
                      (() => { const d = document.getElementById('stripframe').contentDocument; window.__ev = [];
                        ['pointerdown','pointermove','pointerup','mousedown','mousemove','mouseup'].forEach(t =>
                          d.addEventListener(t, e => window.__ev.push(t + ' ' + Math.round(e.clientX) + ',' + Math.round(e.clientY)), true));
                        document.addEventListener('mousedown', e => window.__ev.push('TOP mousedown ' + e.clientX + ',' + e.clientY), true);
                        return 'ok'; })()
                    """) { _ in }
                    self.after(0.3) { self.mouse(.leftMouseDown, x1, y1) }
                    var step = 0.3
                    for i in 1...12 {
                        step += 0.05
                        let x = x1 + (target - x1) * Double(i) / 12
                        self.after(step) { self.mouse(.leftMouseDragged, x, y1) }
                    }
                    self.after(step + 0.2) { self.mouse(.leftMouseUp, target, y1) }
                    self.after(step + 1) {
                        self.js(self.app.mainView, "JSON.stringify(window.__ev.slice(0, 8).concat(['total ' + window.__ev.length]))") { ev in self.results["strip_events"] = ev }
                        self.js(self.app.mainView, thumbs) { v in
                            self.results["strip_afterDrag"] = v
                            self.js(self.app.mainView, "document.getElementById('strip').classList.contains('changed') ? (document.getElementById('ordersave').click(), 'saved') : 'nothing to save'") { r in print("save:", r ?? ""); fflush(stdout) }
                            self.after(4) { self.finishStrip() }
                        }
                    }
                }
            }
        }
    }
    func finishStrip() {
        print("finishing", results["strip_events"] ?? "no events", results["strip_windowContentHeight"] ?? "", (results["strip_afterDrag"] as? [String: Any])?["order"] ?? ""); fflush(stdout)
        snap(app.mainView, "strip") {
            if let d = try? JSONSerialization.data(withJSONObject: self.results, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: self.out.appendingPathComponent("strip.json"))
            }
            NSApp.terminate(nil)
        }
    }

    /// Resize test: the presenter window at several sizes; checks nothing sticks out of the window.
    func runResize() {
        let enc = deck.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? deck
        app.mainView.load(URLRequest(url: URL(string: app.base + "/present/" + enc)!))
        let check = """
        JSON.stringify((() => {
          const out = [...document.querySelectorAll('header, main, #strip, #current, #preview, #notes, #nav, #open')]
            .filter(el => el.offsetParent !== null || el.tagName === 'MAIN')
            .map(el => { const r = el.getBoundingClientRect(); return { id: el.id || el.tagName, r: r.right > innerWidth + 1 || r.bottom > innerHeight + 1 }; })
            .filter(x => x.r).map(x => x.id);
          return { w: innerWidth, h: innerHeight, scrollW: document.documentElement.scrollWidth, scrollH: document.documentElement.scrollHeight, outside: out };
        })())
        """
        let sizes: [NSSize] = [NSSize(width: 1280, height: 800), NSSize(width: 900, height: 560), NSSize(width: 700, height: 900), NSSize(width: 1800, height: 600)]
        func step(_ i: Int) {
            if i == sizes.count { return finishNamed("resize") }
            app.mainWindow.setContentSize(sizes[i])
            if i == 1 { js(app.mainView, "document.getElementById('slides').click(); 'strip'") { _ in } }
            after(2) {
                self.js(self.app.mainView, check) { v in
                    self.results["size_\(Int(sizes[i].width))x\(Int(sizes[i].height))"] = v
                    self.snap(self.app.mainView, "resize-\(i)") { step(i + 1) }
                }
            }
        }
        after(5) { step(0) }
    }
    func finishNamed(_ name: String) {
        if let d = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: out.appendingPathComponent(name + ".json"))
        }
        NSApp.terminate(nil)
    }

    func run() {
        if ProcessInfo.processInfo.environment["LECTERN_SELFTEST_MODE"] == "resize" { return runResize() }
        if ProcessInfo.processInfo.environment["LECTERN_SELFTEST_MODE"] == "strip" { return runStrip() }
        results["screens"] = NSScreen.screens.map { ["builtIn": CGDisplayIsBuiltin($0.displayID) != 0, "frame": NSStringFromRect($0.frame)] }
        let enc = deck.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? deck
        app.mainView.load(URLRequest(url: URL(string: app.base + "/present/" + enc)!))
        after(5) {
            self.js(self.app.mainView, Self.presenterState) { self.results["1_loaded"] = $0 }
            // The "Start presenting" button, as a person would click it.
            self.js(self.app.mainView, "document.getElementById('open').click(); document.querySelector('#startmenu [data-mode=presenter]').click(); 'clicked'") { _ in }
            self.after(5) {
                self.results["2_audienceWindowOpened"] = self.app.audienceWindow != nil
                self.app.focusPresenter()
                // Three clicker presses (Page Down): slide 2, its click-to-reveal step, slide 3.
                self.pageDown()
                self.after(0.6) { self.pageDown() }
                self.after(1.2) { self.pageDown() }
                self.after(3) {
                    self.js(self.app.mainView, Self.presenterState) { p in
                        self.results["3_presenterAfter3PageDowns"] = p
                        self.js(self.app.audienceView, Self.audienceState) { a in
                            self.results["3_audienceAfter3PageDowns"] = a
                            self.blankAndNotes()
                        }
                    }
                }
            }
        }
    }

    func blankAndNotes() {
        press("b", 11) // the clicker's "blank screen" button
        after(1) {
            self.js(self.app.audienceView, Self.audienceState) { a in
                self.results["4_audienceAfterB"] = a
                self.press("b", 11)
                // Type a note in the presenter, as a person would.
                let note = "Self-test note \(Int(Date().timeIntervalSince1970))"
                self.js(self.app.mainView, """
                  (() => { const n = document.getElementById('notes'); n.focus(); n.value = '\(note)';
                           n.dispatchEvent(new Event('input')); return 'typed'; })()
                """) { _ in }
                self.after(2.5) {
                    let notesFile = self.app.server.library.appendingPathComponent(self.deck).appendingPathComponent("notes.md")
                    let text = (try? String(contentsOf: notesFile, encoding: .utf8)) ?? ""
                    self.results["5_noteSavedToNotesMd"] = text.contains(note)
                    self.results["5_notesMdSlideHeadings"] = text.components(separatedBy: "\n## Slide ").count - 1
                    self.js(self.app.mainView, "document.getElementById('notes').blur(); 'ok'") { _ in }
                    self.after(1) { self.finish() }
                }
            }
        }
    }

    func finish() {
        js(app.mainView, Self.presenterState) { p in
            self.results["6_presenterFinal"] = p
            self.js(self.app.audienceView, Self.audienceState) { a in
                self.results["6_audienceFinal"] = a
                self.snap(self.app.mainView, "presenter") {
                    self.snap(self.app.audienceView, "audience") {
                        if let d = try? JSONSerialization.data(withJSONObject: self.results, options: [.prettyPrinted, .sortedKeys]) {
                            try? d.write(to: self.out.appendingPathComponent("results.json"))
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
