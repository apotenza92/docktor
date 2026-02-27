import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var services: AppServices = .live

    private var coordinator: DockExposeCoordinator { Self.services.coordinator }
    private var preferences: Preferences { Self.services.preferences }
    private var updateManager: UpdateManager { Self.services.updateManager }
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("DocktorSettingsWindow")
    private var fallbackSettingsWindow: NSWindow?
    private let legacyAppBundleNames = ["DockActioner.app", "Dockter.app"]
    private let currentAppBundleName = "Docktor.app"
    private let openSettingsLaunchArguments: Set<String> = ["--settings", "-settings", "--open-settings"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateLegacyAppBundleNameIfNeeded()
        Logger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")

        terminateOtherInstances()

        coordinator.startIfPossible()
        updateManager.configureForLaunch(isAutomatedMode: false)

        let isFirstLaunch = !preferences.firstLaunchCompleted
        let launchRequestsSettings = ProcessInfo.processInfo.arguments.contains { openSettingsLaunchArguments.contains($0) }
        let shouldShowWindow = launchRequestsSettings || isFirstLaunch || preferences.showOnStartup
        if launchRequestsSettings {
            Logger.log("Launch argument requested settings window")
        }

        DispatchQueue.main.async {
            if shouldShowWindow {
                self.showSettingsWindow()
            } else {
                self.hideSettingsWindow()
            }
            self.handlePermissionsIfNeeded(allowPrompt: shouldShowWindow)
            if isFirstLaunch {
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

    private func migrateLegacyAppBundleNameIfNeeded() {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard legacyAppBundleNames.contains(currentBundleURL.lastPathComponent) else { return }

        let destinationURL = currentBundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(currentAppBundleName, isDirectory: true)
            .standardizedFileURL
        guard destinationURL.path != currentBundleURL.path else { return }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            Logger.log("Legacy app rename skipped: destination already exists at \(destinationURL.path)")
            return
        }

        do {
            try fileManager.moveItem(at: currentBundleURL, to: destinationURL)
            Logger.log("Renamed legacy app bundle from \(currentBundleURL.lastPathComponent) to \(currentAppBundleName)")
        } catch {
            Logger.log("Legacy app rename failed from \(currentBundleURL.lastPathComponent) to \(currentAppBundleName): \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func handlePermissionsIfNeeded(allowPrompt: Bool) {
        let needsAccessibility = !coordinator.hasAccessibilityPermission
        let needsInputMonitoring = !coordinator.inputMonitoringGranted
        guard needsAccessibility || needsInputMonitoring else { return }

        if allowPrompt && needsAccessibility {
            coordinator.requestAccessibilityPermission()
        }

        if allowPrompt && needsInputMonitoring {
            let delay: TimeInterval = needsAccessibility ? 0.6 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.coordinator.requestInputMonitoringPermission()
                self.coordinator.startWhenPermissionAvailable()
            }
        } else {
            coordinator.startWhenPermissionAvailable()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "docktor" || scheme == "dockter" else {
            return
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "settings" || host == "preferences" || path == "/settings" || path == "/preferences" {
            Logger.log("Received URL request to open settings: \(url.absoluteString)")
            showSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func showSettingsWindow() {
        Logger.log("Opening settings window")
        NSApp.activate(ignoringOtherApps: true)

        if let window = currentSettingsWindow {
            configureSettingsWindow(window)
            window.makeKeyAndOrderFront(nil)
            return
        }

        showFallbackSettingsWindow()
    }

    private func hideSettingsWindow() {
        currentSettingsWindow?.orderOut(nil)
        fallbackSettingsWindow?.orderOut(nil)
    }

    private var currentSettingsWindow: NSWindow? {
        if let fallbackSettingsWindow {
            return fallbackSettingsWindow
        }

        return NSApp.windows.first(where: {
            $0.identifier == settingsWindowIdentifier || $0.title == "Docktor Settings" || $0.title == "Settings"
        })
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.identifier = settingsWindowIdentifier
        window.title = "Docktor Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        sizeSettingsWindowToContent(window)
        window.center()
    }

    private func sizeSettingsWindowToContent(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }
        window.setContentSize(fittingSize)
    }

    private func showFallbackSettingsWindow() {
        if let window = fallbackSettingsWindow {
            configureSettingsWindow(window)
            window.makeKeyAndOrderFront(nil)
            return
        }

        Logger.log("Creating fallback settings window")

        let rootView = PreferencesView(coordinator: coordinator,
                                       updateManager: updateManager,
                                       preferences: preferences)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        let window = NSWindow(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: max(fittingSize.width, 1), height: max(fittingSize.height, 1))),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        configureSettingsWindow(window)
        fallbackSettingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
