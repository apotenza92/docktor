import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var services: AppServices = .live

    private var coordinator: DockExposeCoordinator { Self.services.coordinator }
    private var preferences: Preferences { Self.services.preferences }
    private var updateManager: UpdateManager { Self.services.updateManager }
    private lazy var settingsWindowController = SettingsWindowController(services: Self.services)
    private var menuBarController: MenuBarController?
    private let legacyAppBundleNames = ["DockActioner.app", "Dockter.app"]
    private let currentAppBundleName = "Docktor.app"
    private let openSettingsLaunchArguments: Set<String> = ["--settings", "-settings", "--open-settings"]
    private let openSettingsDistributedNotification = Notification.Name("pzc.Docktor.openSettings")
    private var openSettingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateLegacyAppBundleNameIfNeeded()
        Logger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")

        startObservingOpenSettingsRequests()

        let launchRequestsSettings = ProcessInfo.processInfo.arguments.contains { openSettingsLaunchArguments.contains($0) }
        let launchedFromFinder = isFinderLaunch()
        let explicitSettingsRequest = launchRequestsSettings || launchedFromFinder

        // Important: do NOT hand off Finder launches to an existing instance.
        // Sparkle relaunches and in-app restart flows also look like Finder launches (`-psn_`),
        // and handing those off can cause the freshly launched process to exit.
        let shouldRequestSettingsFromExisting = launchRequestsSettings

        if resolveRunningInstances(shouldRequestSettingsFromExisting: shouldRequestSettingsFromExisting) {
            return
        }

        menuBarController = MenuBarController(preferences: preferences, appDelegate: self)
        coordinator.startIfPossible()
        updateManager.configureForLaunch(isAutomatedMode: false)

        let isFirstLaunch = !preferences.firstLaunchCompleted
        let shouldShowWindow = explicitSettingsRequest || isFirstLaunch || preferences.showOnStartup
        if launchRequestsSettings {
            Logger.log("Launch argument requested settings window")
        }
        if launchedFromFinder {
            Logger.log("Finder launch detected")
        }

        DispatchQueue.main.async {
            if explicitSettingsRequest {
                self.restoreMenuBarIconIfNeeded()
            }
            if shouldShowWindow {
                self.showSettingsWindow()
            }
            self.handlePermissionsIfNeeded(allowPrompt: shouldShowWindow)
            if isFirstLaunch {
                self.preferences.firstLaunchCompleted = true
            }
        }
    }

    private func isFinderLaunch() -> Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-psn_") }
    }

    @discardableResult
    private func resolveRunningInstances(shouldRequestSettingsFromExisting: Bool) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != me }

        guard !others.isEmpty else { return false }

        if shouldRequestSettingsFromExisting {
            Logger.log("Existing instance detected (\(others.map { $0.processIdentifier })); requesting settings open in running instance")
            requestSettingsOpenFromExistingInstance()
            NSApp.terminate(nil)
            return true
        }

        Logger.log("Terminating other running instances: \(others.map { $0.processIdentifier })")
        for app in others {
            _ = app.terminate()
        }
        return false
    }

    private func startObservingOpenSettingsRequests() {
        guard openSettingsObserver == nil else { return }
        let center = DistributedNotificationCenter.default()
        let observedObject = Bundle.main.bundleIdentifier
        openSettingsObserver = center.addObserver(
            forName: openSettingsDistributedNotification,
            object: observedObject,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Logger.log("Received distributed settings-open request")
                self.restoreMenuBarIconIfNeeded()
                self.showSettingsWindow()
            }
        }
    }

    private func requestSettingsOpenFromExistingInstance() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        DistributedNotificationCenter.default().postNotificationName(
            openSettingsDistributedNotification,
            object: bundleId,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func restoreMenuBarIconIfNeeded() {
        guard !preferences.showMenuBarIcon else { return }
        Logger.log("Restoring menu bar icon visibility after explicit settings request")
        preferences.showMenuBarIcon = true
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
        if let openSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(openSettingsObserver)
            self.openSettingsObserver = nil
        }
        coordinator.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Logger.log("Received app reopen request")
        restoreMenuBarIconIfNeeded()
        showSettingsWindow()
        return false
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
            restoreMenuBarIconIfNeeded()
            showSettingsWindow()
        }
    }

    func showSettingsWindow() {
        Logger.log("Opening settings window")
        settingsWindowController.show()
    }
}
