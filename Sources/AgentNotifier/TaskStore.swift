import Foundation
import Combine

enum TaskState: String {
    case running, waiting, done
}

struct AgentTask: Identifiable {
    let id: String          // "tool/session_id"
    let tool: String        // claude | codex
    let project: String     // basename of cwd
    let cwd: String
    var state: TaskState
    let firstSeen: Date
    var lastUpdate: Date
    var doneSince: Date?
    var isStale: Bool
    var prompt: String      // most-recent user prompt for this session (display label)
}

/// Aggregates spool events into a live task list. All mutation happens on the
/// main thread (tailer dispatches to main; the timer fires on the main runloop),
/// so SwiftUI @Published updates are safe.
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AgentTask] = []

    private var index: [String: AgentTask] = [:]
    private var timer: Timer?

    /// Called when a task changes state (prev may be nil for a brand-new task).
    var onTransition: ((AgentTask, TaskState?, TaskState) -> Void)?

    // A "running" task that hasn't emitted any event for this long is treated as
    // stale (terminal closed / process killed before Stop fired) → dimmed gray.
    let staleThreshold: TimeInterval = 120

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func ingest(_ ev: SpoolEvent) {
        guard let newState = TaskState(rawValue: ev.state) else { return }

        // Filter noise: sessions with no project (empty cwd) or rooted directly
        // at the home dir. These are the desktop app's internal background
        // helper sessions — they'd otherwise show confusingly as the username
        // ("raf") rather than a real project name.
        let cwd = ev.cwd.hasSuffix("/") ? String(ev.cwd.dropLast()) : ev.cwd
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.isEmpty || cwd == home { return }

        let key = "\(ev.tool)/\(ev.sessionID)"
        let now = ev.ts > 0 ? Date(timeIntervalSince1970: ev.ts) : Date()
        let project = ev.cwd.isEmpty ? "(unknown)" : (ev.cwd as NSString).lastPathComponent

        var prevState: TaskState?
        if var existing = index[key] {
            prevState = existing.state
            existing.state = newState
            existing.lastUpdate = now
            existing.isStale = false
            existing.doneSince = (newState == .done) ? now : nil
            if !ev.prompt.isEmpty { existing.prompt = ev.prompt }
            index[key] = existing
        } else {
            index[key] = AgentTask(
                id: key, tool: ev.tool, project: project, cwd: ev.cwd,
                state: newState, firstSeen: now, lastUpdate: now,
                doneSince: newState == .done ? now : nil, isStale: false,
                prompt: ev.prompt
            )
        }

        publish()
        if prevState != newState, let t = index[key] {
            onTransition?(t, prevState, newState)
        }
    }

    /// User acknowledged a task (clicked it / chose "clear") — remove it.
    func dismiss(id: String) {
        index[id] = nil
        publish()
    }

    /// Remove all finished tasks (menu "clear completed").
    func clearDone() {
        for (k, t) in index where t.state == .done { index[k] = nil }
        publish()
    }

    private func tick() {
        let now = Date()
        for (key, var t) in index {
            // done tasks stay lit until acknowledged — no auto-removal.
            if t.state == .running, !t.isStale, now.timeIntervalSince(t.lastUpdate) > staleThreshold {
                t.isStale = true
                index[key] = t
            }
        }
        // Always republish so elapsed-time labels refresh every second.
        publish()
    }

    private func publish() {
        // waiting (needs you) on top, then running, then done at the bottom.
        let order: [TaskState: Int] = [.waiting: 0, .running: 1, .done: 2]
        tasks = index.values.sorted { a, b in
            let oa = order[a.state] ?? 3
            let ob = order[b.state] ?? 3
            if oa != ob { return oa < ob }
            return a.lastUpdate > b.lastUpdate
        }
    }

    var runningCount: Int { index.values.filter { $0.state == .running && !$0.isStale }.count }
    var waitingCount: Int { index.values.filter { $0.state == .waiting }.count }
    var doneCount: Int { index.values.filter { $0.state == .done }.count }
}
