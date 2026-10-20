#!/usr/bin/env bash
# Build claude-notch, install the hook, register it in Claude Code's settings.json, start it at login.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
LABEL=com.claude-notch
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

command -v swiftc >/dev/null || { echo "swiftc not found: run  xcode-select --install"; exit 1; }
mkdir -p "$BIN" "$(dirname "$SETTINGS")" "$HOME/Library/LaunchAgents"

swiftc -O claude-notch.swift -o "$BIN/claude-notch"
rm -f "$BIN/claude-notch-hook" # never write through a symlink
install -m 755 claude-notch-hook.py "$BIN/claude-notch-hook"

python3 - "$SETTINGS" "$BIN/claude-notch-hook" <<'PY'
import json, os, shutil, sys, time

path, cmd = sys.argv[1:]
d = {}
if os.path.exists(path):
    try:
        d = json.load(open(path))
    except ValueError:
        sys.exit(f"{path} is not valid JSON; fix it first. Nothing was changed.")
    shutil.copy(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
hooks = d.setdefault("hooks", {})
for ev in ("Stop", "Notification", "StopFailure"):
    lst = hooks.setdefault(ev, [])
    if not any(h.get("command") == cmd for e in lst for h in e.get("hooks", [])):
        lst.append({"hooks": [{"type": "command", "command": cmd}]})
real = os.path.realpath(path)  # a symlinked settings.json stays a symlink
tmp = real + ".tmp"
json.dump(d, open(tmp, "w"), indent=2)
os.replace(tmp, real)
print(f"hooks registered in {path}")
PY

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN/claude-notch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "claude-notch is running. Try:  claude-notch-hook --test done"
