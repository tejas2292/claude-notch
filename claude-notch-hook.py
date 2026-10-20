#!/usr/bin/env python3
"""Claude Code hook for claude-notch: drops one small event file for the notch app.

Stop -> done, Notification -> input, StopFailure -> blocked. Only the state and the project folder
name are written; the hook payload (prompts, tool input, messages) is never stored.
  claude-notch-hook --test done|input|blocked     show a demo even while a terminal is in front
"""
import json, os, sys, time, uuid
from pathlib import Path

DIR = Path(os.environ.get("CLAUDE_NOTCH_DIR", Path.home() / ".claude-notch"))
STATES = {"Stop": "done", "Notification": "input", "StopFailure": "blocked"}


def main():
    if sys.argv[1:2] == ["--test"]:
        state, project, force = (sys.argv[2:3] or ["done"])[0], "demo", True
    else:
        try:
            p = json.load(sys.stdin)
        except ValueError:
            return
        state = STATES.get(p.get("hook_event_name", ""))
        project, force = Path(p.get("cwd") or "").name or "session", False
    if state not in ("done", "input", "blocked"):
        return
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = DIR / f".{uuid.uuid4().hex}.tmp"  # the app ignores dot-files, so it never reads a half-written event
    tmp.write_text(json.dumps({"state": state, "project": project, "force": force, "ts": time.time()}))
    tmp.replace(DIR / f"{time.time_ns()}.json")


if __name__ == "__main__":
    main()
