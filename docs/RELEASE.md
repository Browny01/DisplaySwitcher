# Release & Distribution

This project builds and runs unsigned for local development. Public
distribution (GitHub Releases, Homebrew Cask) requires signing and
notarization as described below. Nothing here is wired to secrets — CI only
builds and tests.

## Local development (no signing required)

```bash
xcodebuild -project DisplaySwitcher.xcodeproj -scheme DisplaySwitcher \
  -configuration Release -destination 'platform=macOS' build
```

The project uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so Debug and
Release builds run on the local Mac with zero setup. Note: `SMAppService`
launch-at-login registration may not take effect until the app is properly
Developer-ID signed (macOS ignores login-item registration from ad-hoc
signed builds in some configurations). The UI surfaces the system error
instead of failing silently.

## Signing (future releases)

1. Enroll in the Apple Developer Program and create a **Developer ID
   Application** certificate.
2. Set the target's `DEVELOPMENT_TEAM` to the Team ID and change
   `CODE_SIGN_STYLE` to `Automatic` (or keep Manual with the Developer ID
   identity) — keep these changes in release branches, not `main`, so local
   builds stay zero-setup.
3. Archive in Xcode (**Product → Archive**) or via `xcodebuild archive`
   with `-allowProvisioningUpdates` on a maintainer machine.

## Notarization (future releases)

```bash
# Inside the .app bundle directory:
ditto -c -k --keepParent DisplaySwitcher.app DisplaySwitcher.zip
xcrun notarytool submit DisplaySwitcher.zip \
  --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD" \
  --wait
xcrun stapler staple DisplaySwitcher.app
```

Upload the stapled `.app` (as a `.zip` or `.dmg`) to a GitHub Release.
Only maintainers with access to the Apple ID credentials perform this step;
no credentials live in this repository or in CI.

## Homebrew Cask (future)

Once signed + notarized releases exist, add a cask upstream
(`homebrew-cask/Casks/d/displayswitcher.rb`) pointing at the release `.zip`
with the bundle ID `com.displayswitcher.DisplaySwitcher` and a `zap` stanza
removing `~/Library/Application Support/DisplaySwitcher` and the settings
defaults key.

## CI

`.github/workflows/ci.yml` builds the app and runs the unit-test scheme on
`macos-15` for every push to `main` and every pull request. It performs no
signing and publishes no artifacts.
