import AppKit
import SwiftUI
import Combine

/// Owns the floating panel. SwiftUI (via NSHostingController + preferredContentSize)
/// drives the panel size for both the collapsed pill and the expanded list; this
/// controller just keeps the panel's top-right corner anchored (default screen
/// top-right below the menu bar; remembers a dragged position).
final class PanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    private let store: TaskStore
    private let ui: UIState
    private let hosting: NSHostingController<PanelRootView>
    private var cancellables = Set<AnyCancellable>()

    private let inset: CGFloat = 8
    private let defaultsKey = "panelAnchorTopRight"
    private var anchorTopRight: CGPoint = .zero
    private var isAdjusting = false

    init(store: TaskStore, ui: UIState) {
        self.store = store
        self.ui = ui

        let root = PanelRootView(store: store, ui: ui, onSelect: { [weak store] task in
            AppActivator.activate(tool: task.tool)
            // Clicking a finished task = acknowledge it → clear from the list.
            if task.state == .done { store?.dismiss(id: task.id) }
        })
        hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60))
        super.init()

        panel.contentViewController = hosting
        panel.delegate = self

        loadAnchor()
        DispatchQueue.main.async { [weak self] in self?.pinTopRight() }

        // Re-pin immediately when collapse toggles (windowDidResize also fires).
        ui.$collapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.pinTopRight() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func show() {
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in self?.pinTopRight() }
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        else { show() }
    }

    // MARK: - Positioning (top-right anchored; SwiftUI drives the size)

    private func pinTopRight() {
        isAdjusting = true
        let f = panel.frame
        panel.setFrameOrigin(NSPoint(x: anchorTopRight.x - f.width,
                                     y: anchorTopRight.y - f.height))
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
            if s.visibleFrame.insetBy(dx: -2, dy: -2).contains(p) { return true }
        }
        return false
    }

    @objc private func screensChanged() {
        if !anchorOnScreen(anchorTopRight) {
            anchorTopRight = defaultTopRight()
            pinTopRight()
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        pinTopRight()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjusting else { return }
        let f = panel.frame
        anchorTopRight = CGPoint(x: f.maxX, y: f.maxY)
        UserDefaults.standard.set(NSStringFromPoint(anchorTopRight), forKey: defaultsKey)
    }
}
