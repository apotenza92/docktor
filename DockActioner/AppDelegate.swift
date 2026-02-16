import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let coordinator = DockExposeCoordinator.shared
    private let preferences = Preferences.shared

    private var isAutomatedMode: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["DOCKACTIONER_AUTOTEST"] == "1"
            || env["DOCKACTIONER_FUNCTIONAL_TEST"] == "1"
            || env["DOCKACTIONER_TEST_SUITE"] == "1"
            || env["DOCKACTIONER_APPEXPOSE_HOTKEY_TEST"] == "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Logger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")

        terminateOtherInstances()

        configureStatusItem()
        coordinator.startIfPossible()
        handlePermissionsIfNeeded()

        if ProcessInfo.processInfo.environment["DOCKACTIONER_AUTOTEST"] == "1" {
            Logger.log("Autotest enabled via DOCKACTIONER_AUTOTEST=1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.coordinator.runSelfTest()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                Logger.log("Autotest done; terminating")
                NSApp.terminate(nil)
            }
        }

        if ProcessInfo.processInfo.environment["DOCKACTIONER_FUNCTIONAL_TEST"] == "1" {
            Logger.log("Functional test enabled via DOCKACTIONER_FUNCTIONAL_TEST=1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.coordinator.runFunctionalTest()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                Logger.log("Functional test done; terminating")
                NSApp.terminate(nil)
            }
        }

        if ProcessInfo.processInfo.environment["DOCKACTIONER_TEST_SUITE"] == "1" {
            Logger.log("Full test suite enabled via DOCKACTIONER_TEST_SUITE=1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.coordinator.runFullTestSuite()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 90.0) {
                Logger.log("Full test suite timeout; terminating")
                NSApp.terminate(nil)
            }
        }

        if ProcessInfo.processInfo.environment["DOCKACTIONER_APPEXPOSE_HOTKEY_TEST"] == "1" {
            Logger.log("App Expose hotkey test enabled via DOCKACTIONER_APPEXPOSE_HOTKEY_TEST=1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.testAppExposeHotkey()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                Logger.log("App Expose hotkey test complete; terminating")
                NSApp.terminate(nil)
            }
        }
        
        let shouldShowWindow = !isAutomatedMode && (!preferences.firstLaunchCompleted || preferences.showOnStartup)
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

    private func terminateOtherInstances() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != me }

        guard !others.isEmpty else { return }
        Logger.log("Terminating other running instances: \(others.map { $0.processIdentifier })")
        for app in others {
            _ = app.terminate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func configureStatusItem() {
        Logger.log("Configuring status item.")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusBarIcon.image()
        item.button?.image?.isTemplate = true
        item.button?.setAccessibilityLabel("DockActioner")
        statusMenu.delegate = self
        item.menu = statusMenu
        rebuildStatusMenu()
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let preferencesItem = NSMenuItem(title: "Preferences…",
                                         action: #selector(showPreferences),
                                         keyEquivalent: ",")
        preferencesItem.target = self
        statusMenu.addItem(preferencesItem)

        statusMenu.addItem(.separator())

        if !coordinator.accessibilityGranted {
            let item = NSMenuItem(title: "Grant Accessibility…",
                                  action: #selector(promptAccessibility),
                                  keyEquivalent: "")
            item.target = self
            statusMenu.addItem(item)
        }

        if !coordinator.inputMonitoringGranted {
            let item = NSMenuItem(title: "Grant Input Monitoring…",
                                  action: #selector(promptInputMonitoring),
                                  keyEquivalent: "")
            item.target = self
            statusMenu.addItem(item)
        }

        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DockActioner",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
    
    @objc private func showPreferences() {
        showPreferencesWindow()
        NSApp.activate(ignoringOtherApps: true)
        Logger.log("Status menu preferences triggered.")
    }

    @objc private func promptAccessibility() {
        coordinator.requestAccessibilityPermission()
        coordinator.startWhenPermissionAvailable()
        rebuildStatusMenu()
        Logger.log("Status menu accessibility prompt triggered.")
    }

    @objc private func promptInputMonitoring() {
        coordinator.requestInputMonitoringPermission()
        coordinator.startWhenPermissionAvailable()
        rebuildStatusMenu()
        Logger.log("Status menu input monitoring prompt triggered.")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func handlePermissionsIfNeeded() {
        let needsAccessibility = !coordinator.hasAccessibilityPermission
        let needsInputMonitoring = !coordinator.inputMonitoringGranted
        guard needsAccessibility || needsInputMonitoring else { return }

        if needsAccessibility {
            coordinator.requestAccessibilityPermission()
        }
        if needsInputMonitoring {
            coordinator.requestInputMonitoringPermission()
        }
        coordinator.startWhenPermissionAvailable()
        rebuildStatusMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferencesWindow()
        return true
    }

    private func showPreferencesWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<PreferencesView> }) {
            window.title = "DockActioner Settings"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
            window.makeKeyAndOrderFront(nil)
            window.center()
            return
        }
        // Fallback to any available window
        NSApp.activate(ignoringOtherApps: true)
        if let fallback = NSApp.windows.first {
            fallback.title = "DockActioner Settings"
            fallback.titleVisibility = .visible
            fallback.titlebarAppearsTransparent = false
            fallback.isMovableByWindowBackground = false
            fallback.makeKeyAndOrderFront(nil)
        }
    }
    
    private func hidePreferencesWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<PreferencesView> }) {
            window.orderOut(nil)
        }
    }
}
