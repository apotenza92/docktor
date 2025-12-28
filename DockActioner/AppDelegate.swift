import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator = DockExposeCoordinator.shared
    private let preferences = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Logger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")
        configureStatusItem()
        coordinator.startIfPossible()
        handleAccessibilityIfNeeded()
        
        let shouldShowWindow = !preferences.firstLaunchCompleted || preferences.showOnStartup
        DispatchQueue.main.async {
            if shouldShowWindow {
                NSApp.activate(ignoringOtherApps: true)
                self.showPreferencesWindow()
            } else {
                self.hidePreferencesWindow()
            }
            if !self.preferences.firstLaunchCompleted {
                self.preferences.firstLaunchCompleted = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func configureStatusItem() {
        Logger.log("Configuring status item.")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.dock", accessibilityDescription: "DockActioner")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let preferencesItem = NSMenuItem(title: "Preferences…",
                                        action: #selector(showPreferences),
                                        keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        if !coordinator.accessibilityGranted {
            let permissionItem = NSMenuItem(title: "Grant Accessibility…",
                                            action: #selector(promptAccessibility),
                                            keyEquivalent: "")
            permissionItem.target = self
            menu.addItem(permissionItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DockActioner",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }
    
    @objc private func showPreferences() {
        showPreferencesWindow()
        NSApp.activate(ignoringOtherApps: true)
        Logger.log("Status menu preferences triggered.")
    }

    @objc private func promptAccessibility() {
        coordinator.requestAccessibilityPermission()
        coordinator.startWhenPermissionAvailable()
        statusItem?.menu = buildMenu()
        Logger.log("Status menu accessibility prompt triggered.")
    }

    @objc private func revealBundle() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
        Logger.log("Revealed bundle at \(url.path)")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func handleAccessibilityIfNeeded() {
        guard !coordinator.hasAccessibilityPermission else { return }
        coordinator.requestAccessibilityPermission()
        coordinator.startWhenPermissionAvailable()
        revealBundle()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferencesWindow()
        return true
    }

    private func showPreferencesWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<PreferencesView> }) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.makeKeyAndOrderFront(nil)
            window.center()
            return
        }
        // Fallback to any available window
        NSApp.activate(ignoringOtherApps: true)
        if let fallback = NSApp.windows.first {
            fallback.titleVisibility = .hidden
            fallback.titlebarAppearsTransparent = true
            fallback.isMovableByWindowBackground = true
            fallback.makeKeyAndOrderFront(nil)
        }
    }
    
    private func hidePreferencesWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<PreferencesView> }) {
            window.orderOut(nil)
        }
    }
}

