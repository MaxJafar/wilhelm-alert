// The wilhelm-alert mini app: pick a mode, hear it, install it.
// A plain AppKit window — no browser, no localhost, no menu bar item.
//
//   wilhelm-settings --root /path/to/wilhelm

import Cocoa

let repoRoot: String = {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == "--root", let value = it.next() { return value }
    }
    return FileManager.default.currentDirectoryPath
}()

@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var buttons: [NSButton] = []
    private let modes = [
        ("light", "Light", "Just the scream."),
        ("middle", "Middle", "The scream, plus the model screaming at you."),
        ("turbo", "Turbo", "All that, and the overlay shakes itself apart."),
    ]

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/wilhelm-alert/config")
    }

    private var selectedMode: String {
        for (index, button) in buttons.enumerated() where button.state == .on {
            return modes[index].0
        }
        return "light"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width: CGFloat = 460
        let height: CGFloat = 500
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "wilhelm-alert"
        window.delegate = self
        window.center()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var y = height - 60

        let heading = label("When your agent finishes, it screams.", size: 17, bold: true)
        heading.frame = NSRect(x: 28, y: y, width: width - 56, height: 24)
        root.addSubview(heading)
        y -= 34

        let sub = label("Pick how loudly.", size: 12, secondary: true)
        sub.frame = NSRect(x: 28, y: y, width: width - 56, height: 18)
        root.addSubview(sub)
        y -= 34

        let current = readConfiguredMode()
        for (identifier, title, blurb) in modes {
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(modeChanged))
            button.frame = NSRect(x: 28, y: y, width: width - 56, height: 20)
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.state = (identifier == current) ? .on : .off
            root.addSubview(button)
            buttons.append(button)
            y -= 20

            let detail = label(blurb, size: 11, secondary: true)
            detail.frame = NSRect(x: 47, y: y, width: width - 75, height: 16)
            root.addSubview(detail)
            y -= 26
        }

        y -= 6
        let test = NSButton(title: "Test it", target: self, action: #selector(testAlert))
        test.frame = NSRect(x: 28, y: y, width: 110, height: 30)
        test.bezelStyle = .rounded
        test.keyEquivalent = "\r"
        root.addSubview(test)
        y -= 46

        let line = NSBox(frame: NSRect(x: 28, y: y, width: width - 56, height: 1))
        line.boxType = .separator
        root.addSubview(line)
        y -= 30

        let installHeading = label("Install into", size: 13, bold: true)
        installHeading.frame = NSRect(x: 28, y: y, width: width - 56, height: 20)
        root.addSubview(installHeading)
        y -= 34

        for (title, tag) in [("Claude Code", 0), ("Codex", 1)] {
            let name = label(title, size: 12)
            name.frame = NSRect(x: 28, y: y + 6, width: 160, height: 18)
            root.addSubview(name)

            let install = NSButton(title: "Install / Update", target: self, action: #selector(installAgent(_:)))
            install.frame = NSRect(x: width - 190, y: y, width: 162, height: 30)
            install.bezelStyle = .rounded
            install.tag = tag
            root.addSubview(install)
            y -= 40
        }

        status = label("", size: 11, secondary: true)
        status.frame = NSRect(x: 28, y: 20, width: width - 56, height: 34)
        status.maximumNumberOfLines = 2
        root.addSubview(status)

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !FileManager.default.fileExists(atPath: repoRoot + "/sounds") {
            say("Warning: no sounds folder at \(repoRoot)")
        }
    }

    // MARK: - actions

    @objc private func modeChanged(_ sender: NSButton) {
        for button in buttons where button !== sender { button.state = .off }
        writeConfiguredMode(selectedMode)
        say("Mode set to \(selectedMode). Saved to ~/.config/wilhelm-alert/config")
    }

    @objc private func testAlert() {
        run(repoRoot + "/bin/wilhelm-alert", args: [], env: ["WILHELM_ALERT_MODE": selectedMode])
        say("Testing \(selectedMode)…")
    }

    @objc private func installAgent(_ sender: NSButton) {
        let isClaude = sender.tag == 0
        let tool = isClaude ? "claude" : "codex"
        guard let binary = which(tool) else {
            say("Couldn't find `\(tool)` on your PATH.")
            return
        }
        say("Installing into \(isClaude ? "Claude Code" : "Codex")…")

        let marketplace = isClaude
            ? ["plugin", "marketplace", "add", "./"]
            : ["plugin", "marketplace", "add", "."]
        _ = capture(binary, args: marketplace, cwd: repoRoot)

        let add = isClaude
            ? ["plugin", "install", "wilhelm-alert@wilhelm-alert-marketplace"]
            : ["plugin", "add", "wilhelm-alert@wilhelm-alert-marketplace"]
        var output = capture(binary, args: add, cwd: repoRoot)

        // Already-installed copies are pinned by version, so a plain install
        // is a no-op after the first time; update is what refreshes the cache.
        if isClaude, output.contains("already installed") {
            output = capture(binary, args: ["plugin", "update", "wilhelm-alert@wilhelm-alert-marketplace"], cwd: repoRoot)
        }

        let firstLine = output
            .split(separator: "\n")
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? "done"
        say(firstLine.trimmingCharacters(in: .whitespaces))
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // MARK: - helpers

    private func say(_ text: String) { status.stringValue = text }

    private func label(_ text: String, size: CGFloat, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        if secondary { field.textColor = .secondaryLabelColor }
        return field
    }

    private func readConfiguredMode() -> String {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return "light" }
        for line in text.split(separator: "\n") where line.hasPrefix("mode=") {
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        return "light"
    }

    private func writeConfiguredMode(_ mode: String) {
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? "mode=\(mode)\n".write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func which(_ tool: String) -> String? {
        let output = capture("/bin/sh", args: ["-lc", "command -v \(tool)"], cwd: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    @discardableResult
    private func capture(_ path: String, args: [String], cwd: String?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "failed to run \(path)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func run(_ path: String, args: [String], env: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        try? process.run()
    }
}

// NSApplication.delegate is a weak reference, so the controller has to be
// held somewhere that outlives this scope.
var retainedController: AnyObject?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = Controller()
    retainedController = controller
    app.delegate = controller
    app.run()
}
