# Docktor

![Docktor icon](Docktor/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

Docktor is a lightweight macOS menu bar app that lets you run actions by clicking or scrolling on Dock icons.

## Defaults

- First click on an inactive app: `App Expose`
- Click after app activation: `App Expose`
- Scroll up: `Hide Others`
- Scroll down: `Hide App`
- Optional: independent `>1 window only` toggles can gate App Expose for first-click and Active App flows

## Install

Homebrew:

```bash
brew tap apotenza92/tap
brew install --cask apotenza92/tap/docktor
```

Beta (installs as a separate app, `Docktor Beta.app`, so you can keep stable `Docktor.app` installed too):

```bash
brew install --cask apotenza92/tap/docktor@beta
```

Manual:

1. Download the latest zip from GitHub Releases.
2. Move `Docktor.app` (or `Docktor Beta.app`) to `/Applications`.
3. Launch once and grant permissions.

## Open Settings Manually

If the menu bar icon is hidden, you can force-open settings via Terminal:

```bash
open -a Docktor --args --settings
```

Or via URL handler:

```bash
open "docktor://settings"
```

## Required macOS Permissions

- Accessibility
- Input Monitoring

System Settings paths:

- `Privacy & Security > Accessibility`
- `Privacy & Security > Input Monitoring`

## Build

```bash
xcodebuild -project Docktor.xcodeproj -scheme Docktor -configuration Debug build
```

