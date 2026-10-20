#!/usr/bin/env python3
"""Claude Code hook for claude-notch: drops one small event file for the notch app.

Stop -> done, Notification -> input, StopFailure -> blocked, SessionEnd -> end. Written: the state, the project
folder name, the session id and where the session's terminal is (tty, pid, app). The hook payload (prompts,
tool input, messages) is never stored.
  claude-notch-hook --test done|input|blocked     show a demo even while a terminal is in front
"""
import json, os, subprocess, sys, time, uuid
from pathlib import Path

DIR = Path(os.environ.get("CLAUDE_NOTCH_DIR", Path.home() / ".claude-notch"))
STATES = {"Stop": "done", "Notification": "input", "StopFailure": "blocked", "SessionEnd": "end"}


def terminal_of_claude():
    """Hooks have no controlling tty, so walk up the process tree to the first ancestor that has one: claude."""
    pid = os.getppid()
    for _ in range(8):
        try:
            out = subprocess.run(["ps", "-o", "ppid=,tty=", "-p", str(pid)], capture_output=True, text=True, timeout=2).stdout.split()
        except (OSError, subprocess.SubprocessError):
            return 0, ""
        if len(out) < 2:
            return 0, ""
        ppid, tty = out[0], out[1]
        if tty not in ("??", "?"):
            return pid, tty
        pid = int(ppid)
    return 0, ""


def main():
    if sys.argv[1:2] == ["--test"]:
        state, project, sid, force = (sys.argv[2:3] or ["done"])[0], "demo", "demo", True
    else:
        try:
            p = json.load(sys.stdin)
        except ValueError:
            return
        state = STATES.get(p.get("hook_event_name", ""))
        project, sid, force = Path(p.get("cwd") or "").name or "session", p.get("session_id") or "", False
    if state not in ("done", "input", "blocked", "end"):
        return
    ev = {"state": state, "project": project, "sid": sid, "force": force, "ts": time.time()}
    if state != "end":  # the end event only needs the session id; SessionEnd has a 1.5 s budget
        pid, tty = terminal_of_claude()
        ev.update(pid=pid, tty=tty, bundle=os.environ.get("__CFBundleIdentifier", ""))
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = DIR / f".{uuid.uuid4().hex}.tmp"  # the app ignores dot-files, so it never reads a half-written event
    tmp.write_text(json.dumps(ev))
    tmp.replace(DIR / f"{time.time_ns()}.json")


if __name__ == "__main__":
    main()
