# CLAUDE.md

Tendbar — open-source (MIT) macOS menu bar app that watches Claude Code sessions through hooks. Swift 6 (strict
concurrency), SwiftUI `MenuBarExtra`, macOS 26+. UI is English with a Polish translation
(String Catalog `Tendbar/Localizable.xcstrings`, source language `en`); code, commits and docs are English. Claude Code only: no Codex, Cursor or others.

## Architecture (Clean Architecture)

Dependencies point inwards only; the package's targets make the compiler enforce it.

```
Domain  <-  Application  <-  Infrastructure
   ^             ^                 ^
   +-------------+---- App: Presentation, Platform, composition root (App/AppContainer)
```

- `TendbarDomain` — entities and business rules, no I/O and no imports of ours: `Session`, `SessionStore` (how hook
  events move a session between states), `HookEvent`, `UsageStore`/`AccountUsage`/`UsageReading`, `AlertPolicy`,
  `LimitWarnings`, `ProfileName`, `Attention` (reminders, quiet sessions), `ActivityStats` (turns and waits per day),
  `PermissionAsk`.
- `TendbarApplication` — use cases, one class each (`HandleHookEvent`, `OpenSession`, `RecordUsageReading`,
  `CheckLimitWarnings`, `CheckAttention`, `OpenNextSession`, `EndGoneSessions`, `AddProfile`, …, plus `PermissionDesk` holding prompts
  that wait for a banner answer) and the ports they need: repositories, `AlertPresenting`, `ScreenFlashing`,
  `SessionProcessChecking`, `TerminalNavigating`, `HookConnecting`, `AlertSettingsProviding`, `Clock`, and the output ports `SessionsOutput`,
  `UsageOutput` and `ActivityOutput`; `PermissionReply` is the way back to a waiting hook. Use cases never import AppKit, SwiftUI or UserNotifications.
- `TendbarInfrastructure` — adapters that touch files, sockets and processes: the hook wire format (`HookEnvelope`,
  `HookRedaction`, `InboundMessage` maps it to domain values), `HookEventListener`, JSON repositories with storage
  records (`Records.swift` keeps `sessions.json`/`usage.json` stable), `HookInstaller`, `ClaudeProfiles`,
  `TranscriptReader`, `TerminalJump` (plans a jump per terminal), `ProcessCommandRunner` (runs `wezterm`, `kitty`, `tmux`
  without a shell, 2 s timeout), `ProcessTTY`.
- `Tendbar/App` — `TendbarApp` and `AppContainer`, the only code that knows every layer; `PreviewAdapters.swift`
  builds the same container on in-memory adapters for SwiftUI previews.
- `Tendbar/Platform` — adapters that need macOS UI frameworks: `UserNotificationsAdapter` (plays the bird calls itself
  with `NSSound`: Notification Center on macOS 27 swaps a named app sound for a built-in one), `EdgeGlow`,
  `AppleScriptTerminalNavigator`, `GlobalShortcut` (Carbon hot key, no Accessibility permission), `LaunchAtLoginService`, `Preferences` (UserDefaults, also `AlertSettingsProviding`).
- `Tendbar/Presentation` — per feature a view model (observable state; implements the output port where there is one),
  a controller (user intent → use case) and the views. Views import Domain and Application, never Infrastructure.
- `TendbarHook` — `tendbar-hook`, embedded in `Tendbar.app/Contents/MacOS`, uses only Domain and Infrastructure. It
  must never print (SessionStart and UserPromptSubmit stdout becomes Claude's context), never block and never fail.
  The one exception is PermissionRequest: it sends a `PermissionRecord` and waits on the same connection
  (`UnixSocketClient.request`) for the app's answer, printing the hook decision only for Allow or Deny from a banner.
  Every held prompt must get an answer or be released (nil) once the session leaves "waiting for you".
- `tools/make-icon.swift` and `tools/make-sounds.swift` draw the icon and synthesize the bird calls in
  `Tendbar/Sounds`; rerun them after changing either, never add recorded or licensed assets.
- `project.yml` — XcodeGen spec; `Tendbar.xcodeproj` and `Tendbar/Info.plist` are generated, not committed.

Flow of one event: `tendbar-hook` → socket → `HookEventListener` → `InboundMessage.hook(HookEvent)` →
`HandleHookEvent` → `SessionRepository` + `SessionsOutput` (`SessionsViewModel`) + `AlertPresenting`/`ScreenFlashing`.
Tests: `TendbarDomainTests` (rules), `TendbarApplicationTests` (use cases on fakes), `TendbarInfrastructureTests`.

## Rules

- Accounts are separate `CLAUDE_CONFIG_DIR` profiles. Never touch OAuth tokens or the Keychain, never switch or
  rotate accounts, never call unofficial endpoints. Limits come only from the statusLine `rate_limits` input.
- Changing `settings.json` of a Claude profile: back it up first, write atomically, touch only our own hooks and our
  `statusLine` wrapper (the previous command stays base64-encoded after `--next` and is restored on disconnect).
  Only on an explicit user action, never automatically at launch.
- Nothing leaves the Mac: no network calls, no analytics.
- User-facing strings are English literals (SwiftUI `Text` / `String(localized:)`); add the Polish translation of
  every new or changed string to `Localizable.xcstrings` (xcodebuild does not sync the catalog, Xcode does).

## Commands

```bash
make test       # Domain, Application and Infrastructure tests
make build      # xcodegen + xcodebuild (Debug, ad-hoc signed) into build/
make run        # build and open the app
make install    # Release build into /Applications (then "Connect" in the app)
```

Plan: https://claude.ai/artifact/5KoBQbPYDmyNbsJrpXraj8

## App icon

`Tendbar/Assets.xcassets/AppIcon.appiconset` is generated: `swift tools/make-icon.swift Tendbar/Assets.xcassets/AppIcon.appiconset /tmp/preview.png` redraws every size (a bird on a bar, orange = the "needs you" colour). macOS shows it in notifications, so there is no separate notification logo. The menu bar symbol stays a template image on purpose.
