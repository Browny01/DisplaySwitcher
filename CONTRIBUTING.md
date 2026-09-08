# Contributing to DisplaySwitcher

Thanks for considering a contribution! This project is MIT-licensed and built with Swift + SwiftUI for macOS 14+.

## Getting started

```bash
git clone https://github.com/example/DisplaySwitcher.git
cd DisplaySwitcher
open DisplaySwitcher.xcodeproj
```

Build with Xcode 16+ (`⌘B`) and run tests (`⌘U`), or from the command line:

```bash
xcodebuild -project DisplaySwitcher.xcodeproj -scheme DisplaySwitcher -configuration Release build
xcodebuild -project DisplaySwitcher.xcodeproj -scheme DisplaySwitcherTests test
```

There are no Swift package dependencies.

## Ground rules

* Keep display-management logic in `Services/` behind protocols — never call Core Graphics directly from views.
* Never hardcode display IDs, resolutions, positions, or machine-specific values.
* Never add network calls, analytics, or telemetry.
* New permissions (TCC) need a written justification in the PR and README.
* Display-affecting changes must be defensive: validate first, snapshot for rollback, degrade gracefully on ambiguity.
* No TODOs for essential functionality, no dead UI, no buttons that do nothing.

## Pull requests

1. Fork and create a topic branch.
2. Add or update unit tests for matching, coordinate, persistence, or validation logic.
3. Ensure the app builds cleanly and all tests pass.
4. Update the README if behaviour, requirements, or API notes change.
5. Open a PR describing what changed, why, and how you tested it (hardware setups appreciated).

## Reporting bugs

Include: macOS version, Mac model, display models + connection types (HDMI/DP/USB-C), arrangement description, and Console logs filtered for the `DisplaySwitcher` subsystem.

## Code of conduct

By participating you agree to uphold the [Code of Conduct](CODE_OF_CONDUCT.md).
