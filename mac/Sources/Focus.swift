// Do Not Disturb while presenting.
// macOS gives apps no direct switch for Focus. The supported way is the Shortcuts app:
// two tiny shortcuts ("Lectern Do Not Disturb On" and "... Off") that Lectern runs with
// /usr/bin/shortcuts. They are added once (Lectern opens them; you click "Add Shortcut").
import AppKit

final class Focus {
    static let onName = "Lectern Do Not Disturb On"
    static let offName = "Lectern Do Not Disturb Off"
    private var turnedOn = false   // only turn it off again if Lectern turned it on

    /// True when both shortcuts are in the Shortcuts app.
    func installed() -> Bool {
        let names = Set(run(["list"], wait: true).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        return names.contains(Self.onName) && names.contains(Self.offName)
    }

    /// Turns Do Not Disturb on. If the shortcuts are missing, calls `missing` (on the main thread).
    func begin(missing: @escaping () -> Void) {
        guard !turnedOn else { return }
        turnedOn = true
        DispatchQueue.global().async {
            if self.installed() { _ = self.run(["run", Self.onName], wait: true) }
            else { DispatchQueue.main.async { self.turnedOn = false; missing() } }
        }
    }

    /// Turns Do Not Disturb off again, if Lectern turned it on. `wait` is for when the app quits.
    func end(wait: Bool = false) {
        guard turnedOn else { return }
        turnedOn = false
        if wait { _ = run(["run", Self.offName], wait: true) }
        else { DispatchQueue.global().async { _ = self.run(["run", Self.offName], wait: true) } }
    }

    /// Opens the two shortcut files, so the Shortcuts app asks to add them.
    func setUp() {
        for name in ["Lectern Do Not Disturb On", "Lectern Do Not Disturb Off"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "shortcut") { NSWorkspace.shared.open(url) }
        }
    }

    @discardableResult
    private func run(_ args: [String], wait: Bool) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        guard wait else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
