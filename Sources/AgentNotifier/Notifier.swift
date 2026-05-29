import Foundation
import AppKit
import UserNotifications

/// Posts macOS notifications + sound on task state transitions.
///
/// Uses UNUserNotificationCenter so notifications are owned by AgentHUD itself:
/// clicking one activates AgentHUD and we jump to the task's app (via `tool` in
/// userInfo) — instead of the old osascript path, whose notifications were owned
/// by Script Editor and opened its file dialog on click.
///
/// Sound is played via afplay (distinct per transition). If notification
/// authorization isn't granted, we fall back to osascript so the user still
/// gets a banner.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let soundQueue = DispatchQueue(label: "agentnotifier.notifier")

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Diagnostic: append a line to ~/.ag_notifier/notify.log so we can read the
    /// real authorization/delivery state from outside the app.
    private func diag(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let p = (NSString(string: "~/.ag_notifier/notify.log").expandingTildeInPath)
        if let h = FileHandle(forWritingAtPath: p) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: URL(fileURLWithPath: p))
        }
    }

    /// Called at launch: only prompt if the user hasn't decided yet. For a
    /// menu-bar (LSUIElement) app the system prompt often fails to surface
    /// unless the app is momentarily active, so we activate first.
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            self?.diag("launch: authStatus=\(settings.authorizationStatus.rawValue) (0=notDetermined 1=denied 2=authorized 3=provisional) alert=\(settings.alertSetting.rawValue) notifCenter=\(settings.notificationCenterSetting.rawValue)")
            guard settings.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
            center.requestAuthorization(options: [.alert, .sound]) { granted, err in
                self?.diag("requestAuthorization granted=\(granted) err=\(String(describing: err))")
            }
        }
    }

    /// Menu-triggered: prompt if undecided, or jump to System Settings if the
    /// user previously denied (the OS won't show the prompt again once denied).
    func ensureAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            case .denied:
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            default:
                break
            }
        }
    }

    func handle(task: AgentTask, newState: TaskState) {
        switch newState {
        case .waiting:
            notify(task: task,
                   title: "需要你 · \(task.project)",
                   body: "\(task.tool) 正在等待你的输入 / 批准",
                   sound: "Glass")
        case .done:
            notify(task: task,
                   title: "已完成 · \(task.project)",
                   body: "\(task.tool) 跑完了这一轮",
                   sound: "Funk")
        case .running:
            break
        }
    }

    private func notify(task: AgentTask, title: String, body: String, sound: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.userInfo = ["tool": task.tool]   // click → jump to this app
                if let att = Self.iconAttachment() { content.attachments = [att] }
                let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
                center.add(req) { err in
                    if err != nil { self.notifyViaOsascript(title: title, body: body, sound: sound) }
                }
                self.playSound(sound)
            default:
                self.notifyViaOsascript(title: title, body: body, sound: sound)
            }
        }
    }

    /// Attach the app icon so it shows on the notification banner (the bundle
    /// icon alone can be stale in usernoted's cache). Copies the bundled PNG to
    /// a temp file once and reuses it.
    private static var cachedAttachmentURL: URL?
    static func iconAttachment() -> UNNotificationAttachment? {
        if cachedAttachmentURL == nil {
            guard let src = Bundle.main.url(forResource: "NotifIcon", withExtension: "png") else { return nil }
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("AgentHUD-NotifIcon.png")
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
            cachedAttachmentURL = dst
        }
        guard let url = cachedAttachmentURL else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: url, options: nil)
    }

    /// Menu "发送测试通知" — proves the channel end-to-end.
    func sendTest() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            self.diag("sendTest: authStatus=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue)")
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                let content = UNMutableNotificationContent()
                content.title = "AgentHUD 测试"
                content.body = "通知正常工作 ✓"
                if let att = Self.iconAttachment() { content.attachments = [att] }
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(req) { err in self.diag("sendTest UN add err=\(String(describing: err))") }
                self.playSound("Funk")
            } else {
                self.diag("sendTest: NOT authorized → osascript fallback")
                self.notifyViaOsascript(title: "AgentHUD 测试", body: "通知正常工作 ✓（osascript 兜底）", sound: "Funk")
            }
        }
    }

    private func playSound(_ name: String) {
        soundQueue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p.arguments = ["/System/Library/Sounds/\(name).aiff"]
            try? p.run()
        }
    }

    private func notifyViaOsascript(title: String, body: String, sound: String) {
        let script = "display notification \(Self.q(body)) with title \(Self.q(title)) sound name \(Self.q(sound))"
        soundQueue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
        }
    }

    private static func q(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even when AgentHUD is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// Click a notification → jump to the owning app (Claude.app / Codex.app).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let tool = response.notification.request.content.userInfo["tool"] as? String {
            DispatchQueue.main.async { AppActivator.activate(tool: tool) }
        }
        completionHandler()
    }
}
