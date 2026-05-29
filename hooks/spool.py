#!/usr/bin/env python3
"""AgentHUD spool writer.

Invoked by Claude Code / Codex lifecycle hooks. Reads the hook's JSON payload
from stdin (session_id / cwd / hook_event_name / prompt) and appends one
normalized JSON line to ~/.ag_notifier/events.jsonl, which AgentHUD.app tails
live.

Install: copy this file to ~/.ag_notifier/spool.py and wire it into the hooks
(see README "Hook setup").

Usage (from a hook command):
    /usr/bin/python3 ~/.ag_notifier/spool.py <tool> <state>
        <tool>  = claude | codex
        <state> = running | waiting | done

Must be fast and never block the agent: it only appends a small line (O_APPEND
is atomic for lines < PIPE_BUF, so concurrent agents won't interleave) and
exits 0. It never raises on bad input.
"""
import sys
import os
import json
import time

SPOOL_DIR = os.path.expanduser("~/.ag_notifier")
SPOOL_FILE = os.path.join(SPOOL_DIR, "events.jsonl")


def main() -> int:
    tool = sys.argv[1] if len(sys.argv) > 1 else "unknown"   # claude | codex
    state = sys.argv[2] if len(sys.argv) > 2 else "running"  # running | waiting | done

    # Hook payload arrives on stdin as a JSON object. Tolerate empty / malformed.
    raw = ""
    try:
        raw = sys.stdin.read()
    except Exception:
        raw = ""
    try:
        ev = json.loads(raw) if raw.strip() else {}
        if not isinstance(ev, dict):
            ev = {}
    except Exception:
        ev = {}

    # The user's prompt (present on UserPromptSubmit) — used as a readable task
    # label. Collapse whitespace/newlines and cap length to keep the line small.
    prompt = ev.get("prompt", "")
    if not isinstance(prompt, str):
        prompt = ""
    prompt = " ".join(prompt.split())[:120]

    line = json.dumps(
        {
            "ts": time.time(),
            "tool": tool,
            "state": state,
            "session_id": str(ev.get("session_id", "")),
            "cwd": str(ev.get("cwd", "")),
            "event": str(ev.get("hook_event_name", "")),
            "prompt": prompt,
        },
        ensure_ascii=False,
    )

    try:
        os.makedirs(SPOOL_DIR, exist_ok=True)
        with open(SPOOL_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        # Never let a logging failure surface back into the agent.
        pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
