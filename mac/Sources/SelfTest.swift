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

    func run() {
        results["screens"] = NSScreen.screens.map { ["builtIn": CGDisplayIsBuiltin($0.displayID) != 0, "frame": NSStringFromRect($0.frame)] }
        let enc = deck.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? deck
        app.mainView.load(URLRequest(url: URL(string: app.base + "/present/" + enc)!))
        after(5) {
            self.js(self.app.mainView, Self.presenterState) { self.results["1_loaded"] = $0 }
            // The "Start presenting" button, as a person would click it.
            self.js(self.app.mainView, "document.getElementById('open').click(); 'clicked'") { _ in }
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
