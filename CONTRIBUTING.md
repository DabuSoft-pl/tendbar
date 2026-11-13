# Contributing

Thanks for wanting to help. Bugs and ideas go in [issues](https://github.com/gruntz12/tendbar/issues); for a bug,
paste the diagnostics from Settings → General.

## Building

You need macOS 14+, Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

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
