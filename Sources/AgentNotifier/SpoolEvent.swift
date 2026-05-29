import Foundation

/// One line of `~/.ag_notifier/events.jsonl`, written by the spool.py hook.
struct SpoolEvent: Codable {
    let ts: Double          // epoch seconds
    let tool: String        // "claude" | "codex"
    let state: String       // "running" | "waiting" | "done"
    let sessionID: String
    let cwd: String
    let event: String
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case ts, tool, state
        case sessionID = "session_id"
        case cwd, event, prompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = (try? c.decode(Double.self, forKey: .ts)) ?? 0
        tool = (try? c.decode(String.self, forKey: .tool)) ?? "unknown"
        state = (try? c.decode(String.self, forKey: .state)) ?? "running"
        sessionID = (try? c.decode(String.self, forKey: .sessionID)) ?? ""
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
        event = (try? c.decode(String.self, forKey: .event)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
    }
}
