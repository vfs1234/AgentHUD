import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService.mainApp for launch-at-login.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        do { try SMAppService.mainApp.register() }
        catch { NSLog("[AgentNotifier] login register failed: \(error)") }
    }

    static func disable() {
        do { try SMAppService.mainApp.unregister() }
        catch { NSLog("[AgentNotifier] login unregister failed: \(error)") }
    }

    static func toggle() {
        isEnabled ? disable() : enable()
    }

    /// On first launch, enable launch-at-login once (user requested guaranteed
    /// auto-start). Afterwards the user controls it via the menu.
    static func enableOnFirstRun() {
        let key = "didEnableLoginItemOnce"
        if !UserDefaults.standard.bool(forKey: key) {
            enable()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}
