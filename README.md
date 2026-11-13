# Tendbar

[![Test](https://github.com/gruntz12/tendbar/actions/workflows/test.yml/badge.svg)](https://github.com/gruntz12/tendbar/actions/workflows/test.yml)

A macOS menu bar app that keeps an eye on your Claude Code sessions. It tells you when a session is done, waiting for
you or failed, takes you back to the right terminal tab, and shows how much of your usage limits each Claude account
has used. Everything stays on your Mac: no account, no network calls, no model calls.

## What it does

- **Sessions.** The menu bar panel lists every session with its folder, state and the start of Claude's last reply.
  A single mark shows the state: a ring while Claude works, orange when it waits for you, red after an error, green
  until you have read a finished reply. Clicking a session switches to its tab in iTerm2 or Terminal, its pane in
  WezTerm, kitty (with `allow_remote_control` and `listen_on` set) or tmux, and its folder's window in VS Code and its
  forks (Cursor and others). For other terminals (Ghostty, Warp) Tendbar brings the app forward.
- **Notifications.** A banner when a session needs you, finishes or fails, each switchable. A "done" banner shows only the folder unless you turn on the start of the reply. Optionally the screen
  edge glows when a session waits or fails. Clicking a banner opens the session.
- **Notch pill.** A small pill next to the notch (or at the middle of the menu bar) shows the lead state and a count,
  with two thin lines for the five-hour and weekly limits. Hover it to see the sessions and every account's limits.
- **Usage limits.** Five-hour and weekly usage per account, with a warning at 80% and 90% of each window.
- **Several accounts.** Readings are filed under the account signed in at the time, so switching accounts in any
  way starts a new entry and the previous account keeps its last reading until its window resets. Separate
  `CLAUDE_CONFIG_DIR` profiles can be added in Settings → Claude Code.

Tendbar never switches or rotates accounts, never reads tokens or the Keychain and never calls Anthropic.

## How it works

Claude Code runs `tendbar-hook` (shipped inside the app bundle) on each hook event. The helper keeps only the fields
Tendbar uses, adds the terminal context (`TERM_PROGRAM`, the host app's bundle id, iTerm/Terminal session ids, WezTerm, kitty and tmux
pane ids and sockets, the TTY, `CLAUDE_CONFIG_DIR`),
sends the event over a Unix socket (`~/Library/Application Support/Tendbar/tendbar.sock`, mode 0600) and exits at
once. It prints nothing and always exits 0, so Claude Code is never slowed down or blocked, even when the app is not
running.

Limits come from the `rate_limits` Claude Code passes to status lines (five-hour and weekly windows, Pro and Max
plans, after the first reply of a session). Connecting wraps the profile's `statusLine`: `tendbar-hook --statusline`
sends the limits to the app, then runs your previous status line command with the same input and prints its output
unchanged. The previous command is kept base64-encoded after `--next`, and disconnecting puts it back.

## What Tendbar stores

Everything lives in `~/Library/Application Support/Tendbar` (folder 0700, files 0600):

| File | Contents |
|---|---|
| `sessions.json` | Session id, folder, terminal ids, state, the permission message and the first 200 characters of the last reply |
| `usage.json` | Limit readings per account, keyed by config directory and e-mail address |
| `events.jsonl` | Only when Settings → General → "Event log" is on (off by default; turning it off deletes it). A debug log of hook events, rotated at 5 MB: session id, event, folder, transcript path, message, notification type, error type and details of a failed turn, and limits when they change. A run of tool calls is logged once |

Prompts, tool inputs and outputs, file contents and Claude's replies are dropped by the helper before they reach the
app. The last reply preview is read from the local transcript file.

## Install

```bash
make install   # Release build into /Applications/Tendbar.app
```

Open Settings (the gear in the panel, or ⌘,) → Claude Code and press "Connect". It adds Tendbar's hooks to
`~/.claude/settings.json` and wraps the status line, after a backup of the file (the last five are kept). "Disconnect"
removes only Tendbar's entries. Settings change only when you press one of these buttons, never at launch. The file
is rewritten with sorted keys.

Keep the app in `/Applications`: the hooks point at the helper inside it.

Settings → General → "Open at login" keeps Tendbar running after a restart.

## Develop

```bash
make test       # Domain, Application and Infrastructure tests
make run        # generate the Xcode project (XcodeGen), build and open the app
make install    # Release build into /Applications
```

The code follows Clean Architecture (domain, use cases, adapters); `CLAUDE.md` describes the layers. The app
icon is drawn by `tools/make-icon.swift`.

## Languages

English and Polish, following the macOS language. To pick one for Tendbar only: System Settings → General →
Language & Region → Applications.

## Requirements

macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen). Builds are signed ad hoc, so they run on the
Mac that built them.

## License

MIT
