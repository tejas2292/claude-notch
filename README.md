# claude-notch

A tiny Dynamic-Island-style alert for [Claude Code](https://claude.com/claude-code) on a MacBook. Start a long
task, go and do something else, and a pixel robot drops out of the notch when Claude is **done**, **needs you**,
or is **blocked**.

| Done | Needs your input | Blocked |
|---|---|---|
| ![done](docs/done.png) | ![input](docs/input.png) | ![blocked](docs/blocked.png) |

The robot waves and bounces when Claude is done, raises both arms when it is waiting for you, and shakes with tired
eyes when it hit a limit or an error. "Done" fades after a few seconds; the other two stay until you click them.

## Install

Needs macOS 14 or later, Xcode command line tools (`xcode-select --install`) and `python3`.

```sh
git clone https://github.com/tejas2292/claude-notch
cd claude-notch
./install.sh
claude-notch-hook --test done      # also: input, blocked
```

`install.sh` compiles one Swift file, copies the hook to `~/.local/bin`, adds three hooks (`Stop`, `Notification`,
`StopFailure`) to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`) after backing it up, and starts
the app at login. Re-running it is safe. `./uninstall.sh` removes all of it.

## How it works

Claude Code runs `claude-notch-hook` on each event. The hook writes one small file into `~/.claude-notch/`. The app
polls that folder and animates the panel.

- **Stop** shows *All done*, **Notification** shows *Needs your input*, **StopFailure** shows *Blocked*.
- A "done" banner is skipped while a terminal (Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, VS Code, Cursor) is
  the front app, since you are already looking at it. The other two always show.
- A short sound plays per state. Mute it with `touch ~/.claude-notch/mute`.

## What it does not do

Privacy is the point of keeping it small:

- It stores **only** the state and the project folder name. It never stores or reads your prompts, tool input,
  Claude's messages or the session transcript.
- No network access and no listening socket. The app and the hook only share files in `~/.claude-notch/`.
- It cannot approve permission prompts or send replies to Claude. It only tells you to go back to the terminal.

## Limits

- Tested on one MacBook with a notch. On a Mac without a notch it should show a small pill at the top centre, but
  that is untested.
- Which moments Claude Code reports through `Notification` (permission prompts, questions, idle waiting) is up to
  Claude Code. If a moment you care about does not trigger the robot, open an issue with what happened.
- The robot is original pixel art in the spirit of the Claude Code mascot, not Anthropic's artwork.

## Alternatives

Other projects do notch notifications for Claude Code, with more features (session lists, approving permissions
from the notch): [cc-island](https://github.com/bistin/cc-island),
[Vibe Notch](https://github.com/farouqaldori/vibe-notch), [Notch Island](https://github.com/AEllison98/notch-island).
This one is the small, read-nothing version.

## Disclaimer

Independent project, not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are trademarks of
Anthropic. MIT licence.
