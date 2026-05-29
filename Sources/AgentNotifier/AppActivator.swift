import AppKit

/// Brings the desktop app that owns a given agent task to the front.
/// The user runs claude inside Claude.app and codex inside Codex.app, so the
/// mapping is fixed and reliable (no terminal-detection needed).
enum AppActivator {
    private static let map: [String: String] = [
        "claude": "/Applications/Claude.app",
        "codex":  "/Applications/Codex.app",
    ]

    static func activate(tool: String) {
        guard let path = map[tool] else { return }
        let url = URL(fileURLWithPath: path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        // openApplication activates the running instance, or launches it if needed.
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }
}
