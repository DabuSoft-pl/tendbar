# CLAUDE.md

Tendbar — open-source (MIT) macOS menu bar app that watches Claude Code sessions through hooks. Swift 6 (strict
concurrency), SwiftUI `MenuBarExtra`, macOS 14+. UI is Polish (String Catalog, source language `pl`), ready for more
languages; code, commits and docs are English. Claude Code only: no Codex, Cursor or others.

## Layout

- `Packages/TendbarKit` — logic shared by the app and the helper, tested with Swift Testing (`swift test`): hook
  envelope and payload, Unix socket client/server, controlling TTY lookup, paths.
- `TendbarHook` — `tendbar-hook`, embedded in `Tendbar.app/Contents/MacOS`. Reads the hook JSON from stdin, adds the
  terminal context, sends it to the app and exits 0. It must never print (SessionStart and UserPromptSubmit stdout
  becomes Claude's context), never block and never fail the hook.
- `Tendbar` — the app: `AppModel` (receives events), `EventLog` (`events.jsonl` in Application Support),
  `MenuContent` (UI).
- `project.yml` — XcodeGen spec; `Tendbar.xcodeproj` and `Tendbar/Info.plist` are generated, not committed.

## Rules

- Accounts are separate `CLAUDE_CONFIG_DIR` profiles. Never touch OAuth tokens or the Keychain, never switch or
  rotate accounts, never call unofficial endpoints. Limits come only from the statusLine `rate_limits` input.
- Changing `settings.json` of a Claude profile: back it up first, write atomically, touch only our own hooks.
- Nothing leaves the Mac: no network calls, no analytics.
- User-facing strings are Polish literals (SwiftUI `Text` / `String(localized:)`), so they land in the catalog.

## Commands

```bash
make test       # TendbarKit tests
make build      # xcodegen + xcodebuild (Debug, ad-hoc signed) into build/
make run        # build and open the app
```

Plan: https://claude.ai/artifact/5KoBQbPYDmyNbsJrpXraj8
