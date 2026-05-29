import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    var onSelect: (AgentTask) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.tasks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    Text("没有运行中的任务")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
            } else {
                ForEach(store.tasks) { task in
                    Button { onSelect(task) } label: { TaskRow(task: task) }
                        .buttonStyle(.plain)
                        .help("点击切换到 \(task.tool == "codex" ? "Codex" : "Claude")")
                }
            }
        }
        .padding(10)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct TaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(state: task.state, isStale: task.isStale)
            VStack(alignment: .leading, spacing: 1) {
                (Text(task.project).font(.system(size: 12, weight: .medium))
                 + Text("  \(task.tool)").font(.system(size: 10)).foregroundColor(.secondary))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            ElapsedText(since: task.firstSeen)
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .opacity(task.isStale ? 0.5 : 1)   // stale 整行变淡 = 不用在意
    }

    // Line 2: show what the agent is working on (first prompt of the turn);
    // fall back to the state text until a prompt has been captured.
    private var subtitle: String {
        task.prompt.isEmpty ? stateText : task.prompt
    }

    private var stateText: String {
        if task.isStale { return "无响应" }
        switch task.state {
        case .running: return "运行中"
        case .waiting: return "等待你"
        case .done:    return "已完成"
        }
    }
}

/// Animated status dot:
///   waiting → red,   fast blink (most attention-grabbing)
///   running → blue,  slow breathing
///   done    → green, steady with a soft glow (success)
///   stale   → gray,  dim & static (ignore me)
private struct StatusDot: View {
    let state: TaskState
    let isStale: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !animated)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .opacity(opacity(at: t))
                .shadow(color: color.opacity(glow(at: t)), radius: 4)
        }
        .frame(width: 9, height: 9)
    }

    private var animated: Bool {
        !isStale && (state == .running || state == .waiting)
    }

    private var color: Color {
        if isStale { return .gray }
        switch state {
        case .waiting: return .red
        case .running: return .blue
        case .done:    return .green
        }
    }

    private func opacity(at t: Double) -> Double {
        guard animated else { return isStale ? 0.7 : 1 }
        switch state {
        case .waiting: return 0.30 + 0.70 * (0.5 + 0.5 * sin(t * 5.2))   // blink
        case .running: return 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2.2))   // breathe
        default:       return 1
        }
    }

    private func glow(at t: Double) -> Double {
        if isStale { return 0 }
        switch state {
        case .done:    return 0.6                       // steady soft glow
        case .waiting: return 0.5 * opacity(at: t)
        case .running: return 0.4 * opacity(at: t)
        }
    }
}

/// Elapsed time, self-updating every second via TimelineView (so it ticks even
/// without the store republishing — keeps the dot animation uninterrupted).
private struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(format(ctx.date.timeIntervalSince(since)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ s: Double) -> String {
        let secs = max(0, Int(s))
        if secs < 60 { return "\(secs)s" }
        let m = secs / 60, ss = secs % 60
        if m < 60 { return "\(m)m\(ss)s" }
        let h = m / 60, mm = m % 60
        return "\(h)h\(mm)m"
    }
}
