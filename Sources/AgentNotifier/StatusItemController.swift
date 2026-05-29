import AppKit
import Combine

/// Owns the menu-bar status item. The icon summarizes state with color; the
/// dropdown lists current tasks (click to jump / clear) plus settings.
/// Color = do-I-care: red waiting > blue running > green done-pending.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: TaskStore
    private let panelController: PanelController
    private let notifier: Notifier
    private var cancellable: AnyCancellable?

    init(store: TaskStore, panelController: PanelController, notifier: Notifier) {
        self.store = store
        self.panelController = panelController
        self.notifier = notifier
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        cancellable = store.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        updateButton()
        rebuildMenu()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let waiting = store.waitingCount
        let running = store.runningCount
        let done = store.doneCount

        // Priority: waiting (act now) → running (in progress) → done (results ready) → idle
        let symbol: String
        let color: NSColor
        let count: Int
        if waiting > 0 {
            symbol = "exclamationmark.triangle.fill"; color = .systemRed; count = waiting
        } else if running > 0 {
            symbol = "circle.fill"; color = .systemBlue; count = running
        } else if done > 0 {
            symbol = "checkmark.circle.fill"; color = .systemGreen; count = done
        } else {
            symbol = "circle.dashed"; color = .secondaryLabelColor; count = 0
        }

        let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentHUD")?
            .withSymbolConfiguration(cfg)
        button.imagePosition = .imageLeading
        button.title = count > 0 ? " \(count)" : ""
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if store.tasks.isEmpty {
            let none = NSMenuItem(title: "没有运行中的任务", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            let header = NSMenuItem(title: "点击任务 → 切到对应 App（已完成的会清除）", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for t in store.tasks {
                let item = NSMenuItem(
                    title: "\(dot(t)) \(t.project) · \(t.tool) · \(stateText(t))",
                    action: #selector(selectTask(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = t.id   // jump by tool + maybe dismiss by id
                menu.addItem(item)
            }
            if store.doneCount > 0 {
                let clear = NSMenuItem(title: "清除已完成（\(store.doneCount)）", action: #selector(clearDone), keyEquivalent: "")
                clear.target = self
                menu.addItem(clear)
            }
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "显示 / 隐藏浮窗", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let notif = NSMenuItem(title: "开启通知权限", action: #selector(enableNotifications), keyEquivalent: "")
        notif.target = self
        menu.addItem(notif)

        let testNotif = NSMenuItem(title: "发送测试通知", action: #selector(sendTestNotification), keyEquivalent: "")
        testNotif.target = self
        menu.addItem(testNotif)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func dot(_ t: AgentTask) -> String {
        if t.isStale { return "○" }
        switch t.state {
        case .waiting: return "🔴"
        case .running: return "🔵"
        case .done:    return "🟢"
        }
    }

    private func stateText(_ t: AgentTask) -> String {
        if t.isStale { return "无响应" }
        switch t.state {
        case .running: return "运行中"
        case .waiting: return "等待你"
        case .done:    return "已完成"
        }
    }

    @objc private func selectTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let task = store.tasks.first(where: { $0.id == id }) else { return }
        AppActivator.activate(tool: task.tool)
        if task.state == .done { store.dismiss(id: id) }
    }

    @objc private func clearDone() { store.clearDone() }
    @objc private func enableNotifications() { notifier.ensureAuthorization() }
    @objc private func sendTestNotification() { notifier.sendTest() }
    @objc private func togglePanel() { panelController.toggle() }
    @objc private func toggleLogin() { LoginItem.toggle(); refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}
