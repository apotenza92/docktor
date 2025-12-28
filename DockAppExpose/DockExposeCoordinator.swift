import AppKit
import Combine

@MainActor
final class DockExposeCoordinator: ObservableObject {
    static let shared = DockExposeCoordinator()

    private let eventTap = DockClickEventTap()
    private let invoker = AppExposeInvoker()
    private let preferences = Preferences.shared
    private var permissionPollTimer: Timer?
    private var lastTriggeredBundle: String? // Track which app we last triggered Exposé for - ignore clicks on same app until different app is clicked
    private var currentExposeApp: String? // Track which app's windows are currently being shown in App Exposé (can differ from lastTriggeredBundle)
    private var appsWithoutWindowsInExpose: Set<String> = [] // Track apps clicked in App Exposé that have no windows
    private var lastScrollBundle: String?
    private var lastScrollDirection: ScrollDirection?
    private var lastScrollTime: TimeInterval?
    private var lastMinimizeToggleTime: [String: TimeInterval] = [:]
    private let minimizeToggleCooldown: TimeInterval = 1.0

    @Published private(set) var isRunning = false
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

    var isEnabled: Bool {
        isRunning && accessibilityGranted
    }

    // Backwards compatibility for callers expecting this name.
    var hasAccessibilityPermission: Bool {
        accessibilityGranted
    }

    func startIfPossible() {
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else {
            Logger.log("startIfPossible: denied (no accessibility).")
            return
        }
        guard !isRunning else {
            Logger.log("startIfPossible: already running.")
            return
        }
        isRunning = eventTap.start(
            clickHandler: { [weak self] point, button, flags in
                return self?.handleClick(at: point, buttonNumber: button, flags: flags) ?? false
            },
            scrollHandler: { [weak self] point, direction, flags in
                return self?.handleScroll(at: point, direction: direction, flags: flags) ?? false
            }
        )
        if !isRunning {
            Logger.log("Failed to start event tap.")
        } else {
            Logger.log("Event tap started.")
        }
    }

    func stop() {
        eventTap.stop()
        isRunning = false
        Logger.log("Event tap stopped.")
    }

    func restart() {
        stop()
        if AXIsProcessTrusted() {
            accessibilityGranted = true
            startIfPossible()
        } else {
            accessibilityGranted = false
            requestAccessibilityPermission()
            startWhenPermissionAvailable()
        }
        Logger.log("Restart requested. Accessibility granted: \(accessibilityGranted)")
    }

    func toggle() {
        if isEnabled {
            stop()
        } else {
            if AXIsProcessTrusted() {
                accessibilityGranted = true
                startIfPossible()
            } else {
                requestAccessibilityPermission()
                startWhenPermissionAvailable()
            }
        }
        Logger.log("Toggle invoked. isEnabled now: \(isEnabled)")
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        Logger.log("Requested accessibility permission prompt.")
    }

    func startWhenPermissionAvailable(pollInterval: TimeInterval = 1.5) {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(timeInterval: pollInterval,
                                                   target: self,
                                                   selector: #selector(handlePermissionPoll(_:)),
                                                   userInfo: nil,
                                                   repeats: true)
    }

    @objc private func handlePermissionPoll(_ timer: Timer) {
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        if trusted {
            timer.invalidate()
            permissionPollTimer = nil
            startIfPossible()
            Logger.log("Accessibility granted detected via polling; started tap.")
        } else {
            Logger.log("Accessibility still not granted; polling continues.")
        }
    }

    private func handleClick(at location: CGPoint, buttonNumber: Int, flags: CGEventFlags) -> Bool {
        Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Logger.log("WORKFLOW: Click received at \(location.x), \(location.y) button \(buttonNumber)")
        guard buttonNumber == 0 else {
            Logger.log("WORKFLOW: Non-primary mouse button \(buttonNumber) - allowing through")
            return false
        }
        
        // Quick synchronous check: get frontmost app and clicked bundle
        let frontmostBefore = FrontmostAppTracker.frontmostBundleIdentifier()
        guard let clickedBundle = DockHitTest.bundleIdentifierAtPoint(location) else {
            // Not a Dock icon - let it pass through immediately
            Logger.log("WORKFLOW: Not a Dock icon, allowing through")
            return false
        }
        
        Logger.log("WORKFLOW: frontmost=\(frontmostBefore ?? "nil"), clicked=\(clickedBundle), lastTriggered=\(lastTriggeredBundle ?? "nil"), currentExpose=\(currentExposeApp ?? "nil")")
        
        // Check if app is running - if not, handle launch in App Exposé
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == clickedBundle }
        if !isRunning && lastTriggeredBundle != nil {
            // App Exposé is active and user clicked an app that isn't running - launch it
            Logger.log("WORKFLOW: App Exposé active, clicked app \(clickedBundle) is not running - launching and deactivating App Exposé")
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            launchApp(bundleIdentifier: clickedBundle)
            return true // Consume event
        }
        
        // First, check if this is a deactivate click on the current Exposé app
        // (This can happen even if frontmost differs, since App Exposé might be showing different app's windows)
        if let currentApp = currentExposeApp, currentApp == clickedBundle, lastTriggeredBundle != nil {
            // Check if this app has no windows (was clicked before without windows)
            if appsWithoutWindowsInExpose.contains(clickedBundle) {
                // Second click on app without windows - activate and show main window
                Logger.log("WORKFLOW: Second click on app without windows (\(clickedBundle)) - activating and showing main window")
                appsWithoutWindowsInExpose.remove(clickedBundle)
                lastTriggeredBundle = nil
                currentExposeApp = nil
                _ = WindowManager.activateAndShowMainWindow(bundleIdentifier: clickedBundle)
                return true // Consume event
            }
            
            // User clicked the app whose windows are currently shown in App Exposé - deactivate and switch to this app
            Logger.log("WORKFLOW: STEP 4 - Deactivate click on currentExposeApp (\(clickedBundle)), activating immediately")
            
            // Clear tracking
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            
            // Activate immediately - no delay
            DispatchQueue.main.async { [weak self] in
                self?.activateApp(bundleIdentifier: clickedBundle)
            }
            return true // Consume event
        }
        
        // If clicking a different app while App Exposé is active, update the current Exposé app
        if frontmostBefore != clickedBundle {
            if lastTriggeredBundle != nil {
                // App Exposé is active - user clicked a different app icon to show its windows
                Logger.log("WORKFLOW: App Exposé active - user clicked different app (\(clickedBundle)) to show its windows")
                
                // Check if this app has windows
                if !WindowManager.hasVisibleWindows(bundleIdentifier: clickedBundle) {
                    Logger.log("WORKFLOW: App \(clickedBundle) has no visible windows - tracking for potential second click")
                    appsWithoutWindowsInExpose.insert(clickedBundle)
                } else {
                    appsWithoutWindowsInExpose.remove(clickedBundle)
                }
                
                currentExposeApp = clickedBundle
                Logger.log("WORKFLOW: Updated currentExposeApp=\(clickedBundle)")
                // Let the event pass through so App Exposé shows this app's windows
                return false
            } else {
                // Normal case: different app clicked, no App Exposé active
                Logger.log("WORKFLOW: STEP 1 - Different app clicked (first activation), allowing Dock activation")
                currentExposeApp = nil
                appsWithoutWindowsInExpose.removeAll()
                return false
            }
        }
        
        // Same app clicked - check if we just triggered Exposé for this app (original trigger app)
        if let lastBundle = lastTriggeredBundle, lastBundle == clickedBundle {
            // User clicked the original app that triggered Exposé - deactivate and stay on that app
            Logger.log("WORKFLOW: STEP 4 - Deactivate click on original trigger app (\(clickedBundle)), staying on this app")
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            // Event passes to Dock, which will close Exposé and keep this app frontmost
            return false
        }
        
        // Execute the configured click action (with modifier-based overrides)
        let baseAction = preferences.clickAction
        let action = resolvedAction(for: baseAction, flags: flags)
        Logger.log("WORKFLOW: Executing click action (button \(buttonNumber)): \(action.rawValue) for \(clickedBundle) (base=\(baseAction.rawValue), flags=\(flags.rawValue))")
        
        switch action {
        case .hideApp:
            if WindowManager.isAppHidden(bundleIdentifier: clickedBundle) {
                _ = WindowManager.unhideApp(bundleIdentifier: clickedBundle)
                _ = WindowManager.activateAndShowMainWindow(bundleIdentifier: clickedBundle)
            } else {
                _ = WindowManager.hideAllWindows(bundleIdentifier: clickedBundle)
            }
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true // Consume event to prevent Dock from processing it
        case .hideOthers:
            if WindowManager.anyHiddenOthers(excluding: clickedBundle) {
                _ = WindowManager.showAllApplications()
            } else {
                _ = WindowManager.hideOthers(bundleIdentifier: clickedBundle)
            }
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true
        case .bringAllToFront:
            if WindowManager.isAppHidden(bundleIdentifier: clickedBundle) {
                _ = WindowManager.unhideApp(bundleIdentifier: clickedBundle)
            }
            _ = WindowManager.bringAllToFront(bundleIdentifier: clickedBundle)
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true
        case .appExpose:
            Logger.log("WORKFLOW: STEP 2 - App Exposé trigger from click, processing (fast path)...")
            triggerAppExpose(for: clickedBundle)
            return true // Consume event
        case .minimizeAll:
            if shouldThrottleMinimize(bundleIdentifier: clickedBundle) {
                Logger.log("WORKFLOW: Minimize throttle active for \(clickedBundle); ignoring click")
                return true
            }
            markMinimize(bundleIdentifier: clickedBundle)
            if WindowManager.allWindowsMinimized(bundleIdentifier: clickedBundle) {
                if WindowManager.restoreAllWindows(bundleIdentifier: clickedBundle) {
                    _ = WindowManager.activateAndShowMainWindow(bundleIdentifier: clickedBundle)
                }
            } else {
                _ = WindowManager.minimizeAllWindows(bundleIdentifier: clickedBundle)
            }
            return true // Consume event to prevent Dock from processing it
        case .quitApp:
            _ = WindowManager.quitApp(bundleIdentifier: clickedBundle)
            return true // Consume event
        @unknown default:
            return false
        }
    }
    
    private func handleScroll(at location: CGPoint, direction: ScrollDirection, flags: CGEventFlags) -> Bool {
        Logger.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Logger.log("WORKFLOW: Scroll \(direction == .up ? "up" : "down") received at \(location.x), \(location.y)")
        
        guard let clickedBundle = DockHitTest.bundleIdentifierAtPoint(location) else {
            // Not a Dock icon - let it pass through immediately
            Logger.log("WORKFLOW: Not a Dock icon, allowing through")
            return false
        }
        
        // Debounce rapid successive scroll events for the same bundle/direction (momentum scrolling)
        let now = Date().timeIntervalSinceReferenceDate
        let debounceWindow: TimeInterval = 0.35
        if let lastTime = lastScrollTime,
           let lastBundle = lastScrollBundle,
           let lastDir = lastScrollDirection,
           lastBundle == clickedBundle,
           lastDir == direction,
           now - lastTime < debounceWindow {
            Logger.log("WORKFLOW: Scroll debounced for \(clickedBundle) direction \(direction == .up ? "up" : "down") (Δ \(now - lastTime))")
            return true // consume to avoid Dock repeat behavior
        }
        lastScrollTime = now
        lastScrollBundle = clickedBundle
        lastScrollDirection = direction
        
        // If App Exposé is active for this app, allow scroll up to close it
        if direction == .up, let current = currentExposeApp, current == clickedBundle, lastTriggeredBundle != nil {
            Logger.log("WORKFLOW: Scroll up detected while App Exposé active for \(clickedBundle) - exiting")
            exitAppExpose()
            return true
        }
        
        // Scroll actions work regardless of if app is active
        let baseAction = direction == .up ? preferences.scrollUpAction : preferences.scrollDownAction
        let action = resolvedAction(for: baseAction, flags: flags)
        Logger.log("WORKFLOW: Executing scroll \(direction == .up ? "up" : "down") action: \(action.rawValue) for \(clickedBundle) (base=\(baseAction.rawValue), flags=\(flags.rawValue))")
        
        switch action {
        case .hideApp:
            if WindowManager.isAppHidden(bundleIdentifier: clickedBundle) {
                _ = WindowManager.unhideApp(bundleIdentifier: clickedBundle)
                _ = WindowManager.activateAndShowMainWindow(bundleIdentifier: clickedBundle)
            } else {
                _ = WindowManager.hideAllWindows(bundleIdentifier: clickedBundle)
            }
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true // Consume event
        case .hideOthers:
            if WindowManager.anyHiddenOthers(excluding: clickedBundle) {
                _ = WindowManager.showAllApplications()
            } else {
                _ = WindowManager.hideOthers(bundleIdentifier: clickedBundle)
            }
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true
        case .bringAllToFront:
            if WindowManager.isAppHidden(bundleIdentifier: clickedBundle) {
                _ = WindowManager.unhideApp(bundleIdentifier: clickedBundle)
            }
            _ = WindowManager.bringAllToFront(bundleIdentifier: clickedBundle)
            lastTriggeredBundle = nil
            currentExposeApp = nil
            appsWithoutWindowsInExpose.removeAll()
            return true
        case .appExpose:
            // Trigger App Exposé for this app (immediate fire for fast double-clicks)
            triggerAppExpose(for: clickedBundle)
            return true // Consume event
        case .minimizeAll:
            if shouldThrottleMinimize(bundleIdentifier: clickedBundle) {
                Logger.log("WORKFLOW: Minimize throttle active for \(clickedBundle); ignoring scroll")
                return true
            }
            markMinimize(bundleIdentifier: clickedBundle)
            if WindowManager.allWindowsMinimized(bundleIdentifier: clickedBundle) {
                if WindowManager.restoreAllWindows(bundleIdentifier: clickedBundle) {
                    _ = WindowManager.activateAndShowMainWindow(bundleIdentifier: clickedBundle)
                }
            } else {
                _ = WindowManager.minimizeAllWindows(bundleIdentifier: clickedBundle)
            }
            return true // Consume event
        case .quitApp:
            _ = WindowManager.quitApp(bundleIdentifier: clickedBundle)
            return true // Consume event
        @unknown default:
            return false
        }
    }
    
    private func shouldThrottleMinimize(bundleIdentifier: String) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastMinimizeToggleTime[bundleIdentifier], now - last < minimizeToggleCooldown {
            return true
        }
        return false
    }
    
    private func markMinimize(bundleIdentifier: String) {
        lastMinimizeToggleTime[bundleIdentifier] = Date().timeIntervalSinceReferenceDate
    }

    private func resolvedAction(for base: DockAction, flags: CGEventFlags) -> DockAction {
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        // Shift overrides: bring to front for hide actions; hide app when base is bringAllToFront
        if hasShift {
            switch base {
            case .hideApp, .hideOthers:
                return .bringAllToFront
            case .bringAllToFront:
                return .hideApp
            default:
                break
            }
        }

        // Option toggles hide app/others; bringAllToFront becomes hide others when option is held
        if hasOption {
            switch base {
            case .hideApp:
                return .hideOthers
            case .hideOthers:
                return .hideApp
            case .bringAllToFront:
                return .hideOthers
            default:
                break
            }
        }

        return base
    }
    
    private func triggerAppExpose(for bundleIdentifier: String) {
        Logger.log("WORKFLOW: Triggering App Exposé for \(bundleIdentifier)")
        
        // Activate the app first if it's not frontmost; use both NSRunningApplication and AppleScript as belt-and-suspenders.
        let frontmost = FrontmostAppTracker.frontmostBundleIdentifier()
        let needsActivation = frontmost != bundleIdentifier
        if needsActivation {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                _ = app.activate(options: [.activateIgnoringOtherApps])
            }
            let script = """
                tell application id "\(bundleIdentifier)"
                    activate
                end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error {
                    Logger.log("WORKFLOW: AppleScript activate for \(bundleIdentifier) error: \(error)")
                }
            }
        }
        
        let fire: @Sendable () -> Void = {
            Task { @MainActor [weak self] in
                guard let self else { return }
                invoker.invokeApplicationWindows(for: bundleIdentifier)
                lastTriggeredBundle = bundleIdentifier
                currentExposeApp = bundleIdentifier
                Logger.log("WORKFLOW: App Exposé triggered for \(bundleIdentifier) (frontmost=\(FrontmostAppTracker.frontmostBundleIdentifier() ?? "nil"))")
            }
        }
        
        // Immediate fire for responsiveness
        fire()
        
        // If activation was needed, schedule a quick retry to ensure the correct app shows after activation completes.
        if needsActivation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: fire)
        }
    }
    
    private func exitAppExpose() {
        Logger.log("WORKFLOW: Exiting App Exposé via Escape")
        // Send Escape key to close App Exposé
        if let source = CGEventSource(stateID: .combinedSessionState) {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
        lastTriggeredBundle = nil
        currentExposeApp = nil
        appsWithoutWindowsInExpose.removeAll()
    }
    
    private func activateApp(bundleIdentifier: String) {
        let beforeActivate = FrontmostAppTracker.frontmostBundleIdentifier()
        Logger.log("WORKFLOW: Activating app \(bundleIdentifier) after App Exposé closed")
        Logger.log("WORKFLOW: Frontmost before activation: \(beforeActivate ?? "nil")")
        
        // Try multiple activation methods for reliability
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            Logger.log("WORKFLOW: Found running app \(bundleIdentifier), attempting activation")
            
            // Method 1: Try NSRunningApplication.activate()
            let success1 = app.activate(options: [.activateIgnoringOtherApps])
            Logger.log("WORKFLOW: NSRunningApplication.activate() returned: \(success1)")
            
            // Method 2: If that failed, try using AppleScript (more reliable)
            if !success1 {
                Logger.log("WORKFLOW: Trying AppleScript activation as fallback")
                let script = """
                    tell application id "\(bundleIdentifier)"
                        activate
                    end tell
                """
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    _ = appleScript.executeAndReturnError(&error)
                    if error != nil {
                        Logger.log("WORKFLOW: AppleScript activation failed: \(error?.description ?? "unknown error")")
                    } else {
                        Logger.log("WORKFLOW: AppleScript activation succeeded")
                    }
                }
            }
            
            // Check frontmost app after a brief moment to see if activation worked
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let afterActivate = FrontmostAppTracker.frontmostBundleIdentifier()
                Logger.log("WORKFLOW: Frontmost after activation (0.1s): \(afterActivate ?? "nil")")
                if afterActivate != bundleIdentifier {
                    Logger.log("WORKFLOW: WARNING - Expected \(bundleIdentifier) but got \(afterActivate ?? "nil")")
                } else {
                    Logger.log("WORKFLOW: SUCCESS - App \(bundleIdentifier) is now frontmost")
                }
            }
        } else {
            Logger.log("WORKFLOW: App \(bundleIdentifier) is not running, cannot activate")
        }
    }
    
    private func launchApp(bundleIdentifier: String) {
        Logger.log("WORKFLOW: Launching app \(bundleIdentifier)")
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        if let url = url {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error = error {
                    Logger.log("WORKFLOW: Failed to launch app \(bundleIdentifier): \(error.localizedDescription)")
                } else {
                    Logger.log("WORKFLOW: Successfully launched app \(bundleIdentifier)")
                }
            }
        } else {
            Logger.log("WORKFLOW: Could not find app URL for \(bundleIdentifier)")
        }
    }
}

