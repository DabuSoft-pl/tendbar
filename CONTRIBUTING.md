# Contributing

Thanks for wanting to help. Bugs and ideas go in [issues](https://github.com/DabuSoft-pl/tendbar/issues); for a bug,
paste the diagnostics from Settings → General.

## Building

You need macOS 26+, Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make test   # Domain, Application and Infrastructure tests
make run    # generate the Xcode project, build and open a Debug build
```

## Pull requests

- Keep a pull request to one change and describe why it is needed.
- Follow the layers in [`CLAUDE.md`](CLAUDE.md): rules in the domain package, use cases behind ports, AppKit and
  SwiftUI only in the app target.
- Add or update tests for domain and use case changes; `make test` must pass.
- UI strings are English. Add the Polish translation of every new string to `Tendbar/Localizable.xcstrings`, or say in
  the pull request that it is missing.
- Nothing may leave the Mac or reach the app that the README's Privacy section rules out.

## Releasing

Maintainers only. Release builds run under the hardened runtime, so `make install` already behaves like a notarized
build. A release needs the "Developer ID Application" certificate of the team in the keychain.

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle compares the build number, so
   it has to grow with every release.
2. Locally: `TEAM_ID=… NOTARY_PROFILE=… make release` signs, notarizes and staples the app and a DMG in
   `build/release` (save the profile once with `xcrun notarytool store-credentials`). `SIGN_IDENTITY=- SKIP_NOTARIZE=1`
   tries the whole script without a certificate. With `gh` signed in, it also makes Sparkle delta updates
   (`Tendbar<build>-<old build>.delta`) from the last two published releases, so an update downloads a few hundred
   kB instead of the whole DMG; `DELTA_COUNT=0` skips them. Upload the DMG, its `.sha256`, `appcast.xml` and every
   `.delta`.
3. Or push a tag `v<version>`: `.github/workflows/release.yml` does the same and attaches the DMG to a draft GitHub
   release. It needs the `TEAM_ID` variable and the secrets listed at the top of the workflow.
4. Check the draft and publish it. The app reads `appcast.xml` from the latest published release, so publishing is
   what offers the update.

Updates are signed with the Sparkle EdDSA key in the maintainer's login keychain (account `tendbar`); its public half
is `SUPublicEDKey` in `project.yml`. Without that private key no installed copy accepts another update, so keep an
export (`generate_keys --account tendbar -x <file>`, the tool is in `build/SourcePackages/artifacts/sparkle/Sparkle/bin`)
somewhere safe; its contents are the `SPARKLE_ED_KEY` secret.
