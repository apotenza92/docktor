# DockActioner

DockActioner is a lightweight macOS menu bar app that adds gesture actions to Dock icons.

- Click action defaults to **App Expose**.
- Scroll down defaults to **Hide App**.
- Scroll up defaults to **Minimize All**.

## Features

- Click active Dock app to trigger configurable window actions.
- Scroll over any Dock icon for quick app/window management.
- App Expose trigger uses Dock notification (`com.apple.expose.front.awake`) for reliability.
- Starts at login (optional) and runs as a menu bar utility.

## Install

### Homebrew (recommended)

```bash
brew tap apotenza92/tap
brew install --cask apotenza92/tap/dock-actioner
```

Beta channel:

```bash
brew install --cask apotenza92/tap/dock-actioner@beta
```

`dock-actioner@beta` installs side-by-side as `DockActioner Beta.app`.

### Manual

1. Download the latest release zip from GitHub Releases.
2. Move the app bundle to `/Applications` (`DockActioner.app` for stable, `DockActioner Beta.app` for beta).
3. Launch once and grant required permissions.

## Permissions

DockActioner requires:

1. **Accessibility** - for Dock hit-testing and app/window actions.
2. **Input Monitoring** - for global click/scroll event taps.

Open from macOS System Settings:

- `Privacy & Security > Accessibility`
- `Privacy & Security > Input Monitoring`

## Usage

Open **Preferences** from the menu bar icon.

### Actions

- Click
  - App Expose (default)
  - Hide App
  - Minimize All
- Scroll Up
  - Minimize All (default)
  - Hide App
  - App Expose
- Scroll Down
  - Hide App (default)
  - Minimize All
  - App Expose

## Build From Source

```bash
xcodebuild -project DockActioner.xcodeproj -scheme DockActioner -configuration Debug build
```

You can also open `DockActioner.xcodeproj` in Xcode and run directly.

## Release and Versioning

Releases are tag-driven via GitHub Actions.

- Pushes to `main` run CI only (build verification).
- Pushing a tag creates signed, notarized release artifacts.

Supported tags:

- Stable: `vX.Y.Z`
- Prerelease: `vX.Y.Z-beta.N`

Create and push a release tag:

```bash
./scripts/release.sh 0.0.1
# or
./scripts/release.sh 0.0.1-beta.1
```

## Signing and Notarization (CI)

Required repository secrets:

- `APPLE_SIGNING_CERTIFICATE_P12_BASE64`
- `APPLE_SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_TEAM_ID`
- `APPLE_NOTARYTOOL_KEY_ID`
- `APPLE_NOTARYTOOL_ISSUER_ID`
- `APPLE_NOTARYTOOL_KEY_P8_BASE64`

Homebrew tap automation (cross-repo push):

- `HOMEBREW_TAP_TOKEN`

### Bootstrapping secrets from your Mac

Useful local commands:

```bash
# Team and signing identities
security find-identity -v -p codesigning

# Export Developer ID cert + private key to .p12 (choose a strong password)
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -o dockactioner-signing.p12

# Base64 encode for GitHub secret APPLE_SIGNING_CERTIFICATE_P12_BASE64
base64 < dockactioner-signing.p12 | pbcopy
```

`APPLE_NOTARYTOOL_KEY_ID`, `APPLE_NOTARYTOOL_ISSUER_ID`, and `APPLE_NOTARYTOOL_KEY_P8_BASE64` come from an App Store Connect API key you generate in App Store Connect.

## Homebrew Tap Automation

Release workflow updates casks in `apotenza92/homebrew-tap`:

- `Casks/dock-actioner.rb`
- `Casks/dock-actioner@beta.rb`

Beta-channel rule matches your other projects: `@beta` tracks whichever is newer between latest stable and latest prerelease.
Beta packages use `DockActioner-Beta-v<version>-macos-<arch>.zip` and install `DockActioner Beta.app`.

## Troubleshooting

### Gestures not firing

- Confirm both permissions are granted.
- Restart DockActioner from Preferences.
- Reopen target app and retry.

### App Expose does not open

- Ensure DockActioner has Accessibility and Input Monitoring permissions.
- Retry after restarting DockActioner.

### Click sound/beep loops

- Update to latest build (click-up/down event consumption and non-keyboard hide/show paths are improved).
- Verify no third-party global shortcut tool conflicts with Dock gestures.
