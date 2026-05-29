import AppKit
import SwiftUI
import Combine

/// Owns the floating panel: hosts the SwiftUI list, sizes the panel to the task
/// count, and keeps its top-right corner anchored (default screen top-right,
/// below the menu bar; remembers the user's dragged position).
final class PanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    private let store: TaskStore
    private var cancellable: AnyCancellable?

    private let width: CGFloat = 300
    private let rowHeight: CGFloat = 30
    private let spacing: CGFloat = 6
    private let padding: CGFloat = 20      // 10 top + 10 bottom (matches TaskListView)
    private let inset: CGFloat = 8
    private let defaultsKey = "panelAnchorTopRight"

    private var anchorTopRight: CGPoint = .zero
    private var isAdjusting = false

    init(store: TaskStore) {
        self.store = store
        let initial = NSRect(x: 0, y: 0, width: width, height: 50)
        panel = FloatingPanel(contentRect: initial)
        super.init()

        let hosting = NSHostingView(rootView: TaskListView(store: store, onSelect: { [weak store] task in
            AppActivator.activate(tool: task.tool)
            // Clicking a finished task = acknowledge it → clear from the list.
            if task.state == .done { store?.dismiss(id: task.id) }
        }))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self

        loadAnchor()
        resize(to: store.tasks.count)

        cancellable = store.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] tasks in self?.resize(to: tasks.count) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func show() { panel.orderFrontRegardless() }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }
    }

    // MARK: - Sizing & positioning

    private func contentHeight(for count: Int) -> CGFloat {
        let rows = max(count, 1)
        return padding + CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
    }

    private func resize(to count: Int) {
        let h = contentHeight(for: count)
        var f = panel.frame
        f.size = NSSize(width: width, height: h)
        f.origin = NSPoint(x: anchorTopRight.x - width, y: anchorTopRight.y - h)
        isAdjusting = true
        panel.setFrame(f, display: true, animate: false)
        isAdjusting = false
    }

    private func loadAnchor() {
        if let s = UserDefaults.standard.string(forKey: defaultsKey) {
            let p = NSPointFromString(s)
            if p != .zero, anchorOnScreen(p) {
                anchorTopRight = p
                return
            }
        }
        anchorTopRight = defaultTopRight()
    }

    private func defaultTopRight() -> CGPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return CGPoint(x: 1440, y: 900)
        }
        let vf = screen.visibleFrame
        return CGPoint(x: vf.maxX - inset, y: vf.maxY - inset)
    }

    private func anchorOnScreen(_ p: CGPoint) -> Bool {
        for s in NSScreen.screens {
            // allow a little slack so an anchor right at the edge still counts
            if s.visibleFrame.insetBy(dx: -2, dy: -2).contains(p) { return true }
        }
        return false
    }

    @objc private func screensChanged() {
        if !anchorOnScreen(anchorTopRight) {
            anchorTopRight = defaultTopRight()
            resize(to: store.tasks.count)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isAdjusting else { return }
        let f = panel.frame
        anchorTopRight = CGPoint(x: f.maxX, y: f.maxY)
        UserDefaults.standard.set(NSStringFromPoint(anchorTopRight), forKey: defaultsKey)
    }
}
