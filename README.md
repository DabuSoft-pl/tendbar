<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="">
</p>

<h1 align="center">Tendbar</h1>

<p align="center">
  Your Claude Code sessions, one glance away in the menu bar.<br>
  Know when a session is done, waiting for you or failed, jump back to its terminal, and watch your usage limits.
</p>

<p align="center">
  <a href="https://github.com/gruntz12/tendbar/actions/workflows/test.yml"><img src="https://github.com/gruntz12/tendbar/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-informational" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/panel-dark.png">
    <img src="docs/images/panel-light.png" width="400" alt="The Tendbar panel: five sessions with their state and last reply, and the usage limits of two accounts">
  </picture>
</p>

Run Claude Code in a few terminals and you end up checking tabs to see which one is done and which one is stuck on a
permission prompt. Tendbar watches them for you. Everything stays on your Mac: no account, no network, no telemetry.

## Features

- **Every session in one list.** Folder, state and the start of Claude's last reply. A ring while Claude works, amber
  when it waits for you, vermilion after an error, sage green until you read a finished reply.
- **Back to the right terminal.** Click a session, or pick it with the arrow keys and press Return, to jump to its
  tab or pane (see [Terminals](#terminals)).
- **Notifications that matter.** A banner when a session needs you, finishes or fails, each one switchable. Optionally
  the screen edge glows in the state's color. Right-click a session to mute its folder.
- **A pill by the notch.** The lead state, a count and two thin lines for the five-hour and weekly limits. Hover it
  for the sessions and every account's limits. On Macs without a notch it sits in the middle of the menu bar.
- **Usage limits per account.** Five-hour and weekly usage with a warning at 80% and 90%, for every account you use,
  including separate `CLAUDE_CONFIG_DIR` profiles. A tick on each bar marks the even pace, and when you run ahead of
  it Tendbar tells you when the limit would run out.
- **Shown your way.** Settings → Appearance picks what sits next to the bird in the menu bar, when the pill shows up,
  and how dense the panel is: with or without reply previews, full or one-line limits.
- **English and Polish.** Follows the macOS language, or pick one in Settings → General.

<p align="center">
  <img src="docs/images/notch-expanded.png" width="520" alt="The notch pill expanded on hover: four sessions and the limits of two accounts">
</p>

## Terminals

| Terminal | Clicking a session |
|---|---|
| Terminal, iTerm2 | Switches to the session's tab |
| WezTerm | Activates the session's pane |
| kitty | Focuses the session's window (needs `allow_remote_control` and `listen_on` in `kitty.conf`) |
| tmux | Selects the pane, then the tab running tmux in Terminal or iTerm2 |
| VS Code, Cursor and other forks | Opens the window of the session's folder |
| Ghostty, Warp, others | Brings the app forward |

## Install

Tendbar is built from source for now (macOS 14+, Xcode 27+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
brew install xcodegen
git clone https://github.com/gruntz12/tendbar.git
cd tendbar
make install   # Release build into /Applications/Tendbar.app
```

Then open Settings (the gear in the panel, or ⌘,) → Claude Code and press **Connect**. Keep the app in
`/Applications`, since the hooks point at the helper inside it. Settings → General → **Open at login** keeps it
running after a restart.

Builds are signed ad hoc, so they run on the Mac that built them.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark.png">
    <img src="docs/images/settings-light.png" width="700" alt="Tendbar settings: the Claude Code connection and the account profiles">
  </picture>
</p>

## Privacy

- **Nothing leaves your Mac.** Tendbar makes no network calls, has no analytics and never calls Anthropic.
- **No secrets.** It never reads tokens or the Keychain and never switches or rotates accounts.
- **Only what it needs.** The hook helper drops prompts, tool inputs and outputs, file contents and Claude's replies
  before anything reaches the app. The reply preview is read from the local transcript file.
- **Not on shared screens.** The pill and the glow stay out of screen sharing and recordings (Settings → General).
- **Your settings, your call.** `~/.claude/settings.json` changes only when you press Connect or Disconnect, never at
  launch. Each change is backed up first (the last five are kept), and Disconnect removes only Tendbar's entries.

Everything Tendbar keeps lives in `~/Library/Application Support/Tendbar` (folder 0700, files 0600):

| File | Contents |
|---|---|
| `sessions.json` | Session id, folder, terminal ids, state, the permission message and the first 200 characters of the last reply |
| `usage.json` | Limit readings per account, keyed by config directory and e-mail address |
| `events.jsonl` | Only when Settings → General → Event log is on (off by default; turning it off deletes it). Hook events for troubleshooting: session id, event, folder, transcript path, message, notification type, the error of a failed turn, and limits when they change. Rotated at 5 MB |

## How it works

Connecting adds Tendbar's hooks to Claude Code. On each hook event Claude Code runs `tendbar-hook`, a small helper
inside the app bundle. It keeps only the fields Tendbar uses, adds the terminal context (`TERM_PROGRAM`, the host
app, iTerm/Terminal session ids, WezTerm, kitty and tmux pane ids and sockets, the TTY, `CLAUDE_CONFIG_DIR`), sends
the event over a Unix socket (`~/Library/Application Support/Tendbar/tendbar.sock`, mode 0600) and exits at once. It
prints nothing and always exits 0, so Claude Code is never slowed down or blocked, even when Tendbar is not running.

Limits come from the `rate_limits` Claude Code passes to status lines (five-hour and weekly windows on Pro and Max
plans, after the first reply of a session). Connecting wraps your `statusLine`: `tendbar-hook --statusline` sends the
limits to the app, then runs your previous status line command with the same input and prints its output unchanged.
Disconnecting puts the previous command back.

Readings are filed under the account signed in at the time, so switching accounts starts a new entry, and the
previous account keeps its last reading until its window resets.

## Develop

```bash
make test         # Domain, Application and Infrastructure tests
make run          # generate the Xcode project, build and open a Debug build
make install      # Release build into /Applications
make screenshots  # render the README images from sample data
```

The code follows Clean Architecture: a domain package, use cases and adapters, described in [`CLAUDE.md`](CLAUDE.md).
UI strings are English, with the Polish translation in `Tendbar/Localizable.xcstrings`. The app icon is drawn by
`tools/make-icon.swift`.

## Contributing

Bugs and ideas are welcome in [issues](https://github.com/gruntz12/tendbar/issues); Settings → General → Diagnostics
copies what a bug report needs without anything private. See [CONTRIBUTING.md](CONTRIBUTING.md), and report security
problems privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Tendbar is an independent project, not affiliated with or endorsed by Anthropic.
