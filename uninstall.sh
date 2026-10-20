#!/usr/bin/env bash
# Remove claude-notch: login item, binaries, and its three hook entries from settings.json.
set -euo pipefail

BIN="$HOME/.local/bin"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
PLIST="$HOME/Library/LaunchAgents/com.claude-notch.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST" "$BIN/claude-notch" "$BIN/claude-notch-hook"

[ -f "$SETTINGS" ] && python3 - "$SETTINGS" "$BIN/claude-notch-hook" <<'PY'
import json, os, shutil, sys, time

path, cmd = sys.argv[1:]
d = json.load(open(path))
shutil.copy(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
hooks = d.get("hooks", {})
for ev in list(hooks):
    hooks[ev] = [e for e in hooks[ev] if not any(h.get("command") == cmd for h in e.get("hooks", []))]
    if not hooks[ev]:
        del hooks[ev]
if not hooks:
    d.pop("hooks", None)
real = os.path.realpath(path)
tmp = real + ".tmp"
json.dump(d, open(tmp, "w"), indent=2)
os.replace(tmp, real)
PY
echo "claude-notch removed. (~/.claude-notch/ holds only transient event files and can be deleted.)"
