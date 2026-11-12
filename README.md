# Tendbar

A macOS menu bar app that keeps an eye on your Claude Code sessions: it tells you when a session is done or waiting
for you, and takes you back to the right terminal tab. Everything stays on your Mac: no account, no network calls,
no model calls.

> Early development: sessions, their state and the last reply already show; jumping to the terminal tab comes next.

## How it works

Claude Code runs `tendbar-hook` (shipped inside the app bundle) on each hook event. The helper adds the terminal
context (`TERM_PROGRAM`, iTerm/Terminal session ids, the TTY, `CLAUDE_CONFIG_DIR`), sends the event over a Unix
socket (`~/Library/Application Support/Tendbar/tendbar.sock`, mode 0600) and exits at once. It prints nothing and
always exits 0, so Claude Code is never slowed down or blocked, even when the app is not running.

## Try it

```bash
make test   # TendbarKit unit tests
make run    # generate the Xcode project (XcodeGen), build and open the app
```

Then add the hook to `~/.claude/settings.json` (use "Kopiuj ścieżkę hooka" in the menu to copy the path):

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "StopFailure": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/path/to/Tendbar.app/Contents/MacOS/tendbar-hook" }] }]
  }
}
```

Or just press "Połącz" in the app: it adds the hooks for you (also `PostToolUse`, so a session leaves "needs you"
once you approve a tool), after a backup of `settings.json` (the last five are kept), and "Rozłącz z Claude Code"
removes only Tendbar's hooks. The file is rewritten with sorted keys.

## Requirements

macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## License

MIT
