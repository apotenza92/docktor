# DockActioner

A macOS application that enhances your Dock with customizable click and scroll gestures for app management.

## Features

- **Click Actions**: Customize what happens when you click an active app's Dock icon
- **Scroll Gestures**: Customize scroll up and scroll down actions on any Dock icon
- **App Exposé Integration**: Trigger App Exposé via gestures
- **Window Management**: Hide, minimize, or expose windows with simple gestures

## Installation

1. Build the project in Xcode or download a pre-built release
2. Copy `DockActioner.app` to `/Applications`
3. Launch the app
4. Grant required permissions when prompted

## Permissions

DockActioner requires two permissions:

### 1. Accessibility Permission
**Required** - Allows the app to detect clicks and scrolls on Dock icons.

To grant:
1. System Settings > Privacy & Security > Accessibility
2. Enable DockActioner

### 2. Automation Permission
**Required** - Allows the app to trigger App Exposé and manage windows.

To grant:
1. System Settings > Privacy & Security > Automation
2. Enable DockActioner for System Events

## Usage

### Click Actions
Click actions only work when the app is **active** (frontmost):

- **Hide App** (default): Hides all windows of the active app (Cmd+H equivalent)
- **App Exposé**: Triggers App Exposé for the active app
- **Minimize All**: Minimizes all windows of the active app to the Dock

### Scroll Gestures
Scroll gestures work on **any** Dock icon, regardless of whether the app is active:

- **Scroll Up** (default: Minimize All): Minimizes all windows of the app
- **Scroll Down** (default: App Exposé): Triggers App Exposé for the app

### Customization

Open Preferences from the menu bar icon or Dock to customize:
- Click action (Hide App, App Exposé, or Minimize All)
- Scroll up action (Hide App, App Exposé, or Minimize All)
- Scroll down action (Hide App, App Exposé, or Minimize All)

### App Exposé Special Behaviors

- **Apps without windows**: If you click an app icon in App Exposé that has no windows, clicking it again will activate the app and show its main window
- **Apps not running**: If you click an app icon in App Exposé that isn't running, the app will launch and App Exposé will close

## Menu Bar

The app appears in your menu bar with a Dock icon. Click it to:
- Enable/Disable the app
- Open Preferences
- Grant Accessibility permission (if needed)
- Quit the app

## Troubleshooting

### App not responding to gestures
1. Check that the app is enabled in Preferences
2. Verify Accessibility permission is granted
3. Try restarting the app from the menu bar

### App Exposé not triggering
1. Verify Automation permission is granted
2. Check your System Settings > Keyboard > Keyboard Shortcuts > Mission Control
3. Ensure "Application windows" shortcut is enabled

### Scroll gestures not working
1. Ensure Accessibility permission is granted
2. Try scrolling more slowly or with more deliberate movements
3. Check that the app is enabled

## Building from Source

1. Clone the repository
2. Open `DockActioner.xcodeproj` in Xcode
3. Build and run (⌘R)
4. The app will be staged to `/Applications` automatically

## License

[Add your license here]

