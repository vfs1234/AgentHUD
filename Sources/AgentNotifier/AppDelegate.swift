import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore!
    private var tailer: SpoolTailer!
    private var statusController: StatusItemController!
    private var panelController: PanelController!
    private var notifier: Notifier!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = TaskStore()
        self.store = store

        let notifier = Notifier()
        self.notifier = notifier
        store.onTransition = { task, _, newState in
            notifier.handle(task: task, newState: newState)
        }

        let panelController = PanelController(store: store)
        self.panelController = panelController
        panelController.show()

        let statusController = StatusItemController(store: store, panelController: panelController, notifier: notifier)
        self.statusController = statusController

        // Surface the notification permission prompt (only if undecided).
        notifier.requestAuthorizationIfNeeded()

        let path = (NSString(string: "~/.ag_notifier/events.jsonl").expandingTildeInPath)
        let tailer = SpoolTailer(path: path) { events in
            for ev in events { store.ingest(ev) }   // delivered on the main queue
        }
        self.tailer = tailer
        tailer.start()

        // User asked for guaranteed auto-start: enable launch-at-login once.
        LoginItem.enableOnFirstRun()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
