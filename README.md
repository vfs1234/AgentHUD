# AgentHUD

A tiny macOS menu-bar app + always-on-top floating panel that shows the live
status of your **Claude Code** and **Codex** agent sessions — so you can tell at
a glance which task is running, which is waiting for you, and which just
finished, without hunting through terminal windows.

Native Swift (AppKit + SwiftUI), no third-party dependencies. Menu-bar only (no
Dock icon), auto-launches at login.

## Screenshots

The floating panel — one row per session, sorted so anything waiting for you is
on top:

<img src="docs/panel.png" width="380" alt="floating panel" />

Each row, explained:

![interface anatomy](docs/anatomy.png)

| Menu-bar badge | Dropdown menu | Notification |
|---|---|---|
| <img src="docs/menubar.png" width="200" alt="menu bar badge" /> | <img src="docs/menu.png" width="320" alt="dropdown menu" /> | <img src="docs/notification.png" width="320" alt="notification" /> |

The badge turns red with a count when something needs you; the dropdown lists
every task (click to jump to its app), with *clear completed*, *launch at login*,
and notification controls.

## What it shows

A compact panel pinned to the top-right of the screen, one row per session:

```
🔵 courseweb  claude            1m20s
   修复支付回调超时并补充失败重试日志
🔴 xbk-web-agent  codex         12s
   把首页改成响应式布局，适配移动端
```

- **Line 1** — project (basename of the session's cwd) + tool
- **Line 2** — the session's latest prompt (what the agent is working on)
- **Right** — elapsed time

### Status colors

| Dot | State | Meaning |
|-----|-------|---------|
| 🔴 red (blinking) | `waiting` | The agent needs you — input or approval |
| 🔵 blue (breathing) | `running` | The agent is working |
| 🟢 green | `done` | The turn finished |
| ⚪ gray (dim) | `stale` | A running task with no events for >120s (terminal closed / killed) |

The menu-bar icon summarizes everything: red + count if anything is waiting,
else blue + count if anything is running, else idle. Click a task (in the panel
or the menu) to jump to its app (Claude.app / Codex.app).

## How it works

![how it works](docs/flow.png)

```
Claude Code hooks ─┐
                   ├─► spool.py <tool> <state>  ──► ~/.ag_notifier/events.jsonl
Codex hooks ───────┘     (reads hook JSON from stdin)        │ (tailed live)
                                                             ▼
                                                   AgentHUD.app
                                          (menu bar + floating panel + notifications)
```

Hooks append one JSON line per lifecycle event to a spool file; the app tails it
and aggregates by `tool/session_id`. The hook side is fire-and-forget (a single
local file append) so it never blocks or slows the agent.

## Requirements

- macOS 14+
- Xcode or Command Line Tools (`swift`, `actool`, `codesign`)

## Build & install

```bash
bash make-icon.sh   # render AppIcon.svg → iconset / Assets.xcassets (only needed if you change the icon)
bash build.sh       # compile, assemble AgentHUD.app, ad-hoc sign, install to ~/Applications
open ~/Applications/AgentHUD.app
```

`build.sh` is idempotent — re-run it after any source change. The app
self-registers as a login item on first launch.

## Hook setup

1. Copy the spool script and make it executable:

   ```bash
   mkdir -p ~/.ag_notifier
   cp hooks/spool.py ~/.ag_notifier/spool.py
   chmod +x ~/.ag_notifier/spool.py
   ```

2. **Claude Code** — add to `~/.claude/settings.json` (use your absolute home path):

   ```json
   "hooks": {
     "SessionStart":     [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py claude running" }] }],
     "UserPromptSubmit": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py claude running" }] }],
     "Notification":     [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py claude waiting" }] }],
     "Stop":             [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py claude done" }] }]
   }
   ```

3. **Codex** — add to `~/.codex/config.toml` (then trust the hooks; leave any existing `notify` line untouched):

   ```toml
   [[hooks.UserPromptSubmit]]
   [[hooks.UserPromptSubmit.hooks]]
   type = "command"
   command = "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py codex running"

   [[hooks.PermissionRequest]]
   [[hooks.PermissionRequest.hooks]]
   type = "command"
   command = "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py codex waiting"

   [[hooks.Stop]]
   [[hooks.Stop.hooks]]
   type = "command"
   command = "/usr/bin/python3 /Users/<you>/.ag_notifier/spool.py codex done"
   ```

   > Codex CLI `exec` (headless) mode does not fire lifecycle hooks — only
   > interactive sessions do.

## Where to tweak

| Want to change | File |
|----------------|------|
| Colors / dot animations / the prompt subtitle line | `Sources/AgentNotifier/TaskListView.swift` |
| Stale threshold (120s), done auto-clear, aggregation, noise filter | `Sources/AgentNotifier/TaskStore.swift` |
| Menu-bar icon + dropdown menu | `Sources/AgentNotifier/StatusItemController.swift` |
| Notification text / sound | `Sources/AgentNotifier/Notifier.swift` |
| Which app a task jumps to | `Sources/AgentNotifier/AppActivator.swift` |
| Panel position / sizing | `Sources/AgentNotifier/PanelController.swift` |
| Spool line format / event→state mapping | `hooks/spool.py` + the hook configs above |

## License

Personal project — use as you like.
