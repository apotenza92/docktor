import AppKit
import ApplicationServices

enum WindowManager {
    /// Hide all windows of an app (Cmd+H equivalent)
    static func hideAllWindows(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running")
            return false
        }
        
        // First try the direct NSRunningApplication hide
        if app.hide() {
            Logger.log("WindowManager: hide() succeeded for \(bundleIdentifier)")
            return true
        }
        
        if app.isHidden {
            Logger.log("WindowManager: App \(bundleIdentifier) already hidden; treating as success")
            return true
        }
        
        // Try Accessibility hide as a stronger fallback
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let hidden: CFBoolean = kCFBooleanTrue
        if AXUIElementSetAttributeValue(appElement, kAXHiddenAttribute as CFString, hidden) == .success {
            Logger.log("WindowManager: AX hide succeeded for \(bundleIdentifier)")
            return true
        } else {
            Logger.log("WindowManager: AX hide failed for \(bundleIdentifier); attempting AppleScript")
        }
        
        let script = """
        tell application id "\(bundleIdentifier)"
            hide
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error != nil {
                Logger.log("WindowManager: Failed to hide app \(bundleIdentifier): \(error?.description ?? "unknown error")")
                return false
            }
            Logger.log("WindowManager: Successfully hid app \(bundleIdentifier)")
            return true
        }
        return false
    }
    
    /// Unhide an app and activate it
    static func unhideApp(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running, cannot unhide")
            return false
        }
        app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        if !activated {
            let script = """
            tell application id "\(bundleIdentifier)"
                activate
            end tell
            """
            _ = runAppleScript(script, context: "Unhide activate \(bundleIdentifier)")
        }
        Logger.log("WindowManager: Unhid and activated \(bundleIdentifier)")
        return true
    }
    
    /// Check if app is hidden
    static func isAppHidden(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })?.isHidden ?? false
    }
    
    /// Minimize all windows of an app to the Dock
    static func minimizeAllWindows(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running")
            return false
        }
        
        if app.isHidden {
            app.unhide()
        }
        let pid = app.processIdentifier
        
        let appElement = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        guard result == .success,
              let windowsArray = windows as? [AXUIElement] else {
            Logger.log("WindowManager: Failed to get windows for \(bundleIdentifier)")
            return false
        }
        
        var minimizedCount = 0
        for window in windowsArray {
            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
               let isMinimized = minimizedValue as? Bool, isMinimized {
                continue // Already minimized
            }
            
            let minimized: CFBoolean = kCFBooleanTrue
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized) == .success {
                minimizedCount += 1
            }
        }
        
        Logger.log("WindowManager: Minimized \(minimizedCount) windows for \(bundleIdentifier)")
        return minimizedCount > 0
        
    }
    
    /// Restore all minimized windows of an app
    static func restoreAllWindows(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running")
            return false
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        guard result == .success,
              let windowsArray = windows as? [AXUIElement] else {
            Logger.log("WindowManager: Failed to get windows for \(bundleIdentifier) when restoring")
            return false
        }
        
        var restoredCount = 0
        for window in windowsArray {
            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
               let isMinimized = minimizedValue as? Bool, isMinimized {
                let minimized: CFBoolean = kCFBooleanFalse
                if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized) == .success {
                    restoredCount += 1
                }
            }
        }
        
        Logger.log("WindowManager: Restored \(restoredCount) windows for \(bundleIdentifier)")
        
        guard restoredCount > 0 else { return false }
        
        // Bring the app to the front; try NSRunningApplication then AppleScript fallback.
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        if !activated {
            let script = """
            tell application id "\(bundleIdentifier)"
                activate
            end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error {
                    Logger.log("WindowManager: AppleScript activate failed for \(bundleIdentifier): \(error)")
                }
            }
        }
        
        // Re-assert frontmost after a short delay to cover race conditions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
        
        return true
    }
    
    /// Check if all windows are minimized (and there is at least one window)
    static func allWindowsMinimized(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        guard result == .success,
              let windowsArray = windows as? [AXUIElement],
              !windowsArray.isEmpty else {
            return false
        }
        
        for window in windowsArray {
            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
               let isMinimized = minimizedValue as? Bool, isMinimized {
                continue
            } else {
                return false
            }
        }
        return true
    }
    
    /// Check if an app has visible windows
    static func hasVisibleWindows(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        
        let pid = app.processIdentifier
        
        let appElement = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        guard result == .success,
              let windowsArray = windows as? [AXUIElement] else {
            return false
        }
        
        for window in windowsArray {
            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
               let isMinimized = minimizedValue as? Bool, isMinimized {
                continue // Skip minimized windows
            }
            
            var hiddenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXHiddenAttribute as CFString, &hiddenValue) == .success,
               let isHidden = hiddenValue as? Bool, isHidden {
                continue // Skip hidden windows
            }
            
            // Found at least one visible, non-minimized window
            return true
        }
        
        return false
    }
    
    /// Get the main window of an app
    static func getMainWindow(bundleIdentifier: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        
        let pid = app.processIdentifier
        
        let appElement = AXUIElementCreateApplication(pid)
        var mainWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        guard result == .success,
              let windowRef = mainWindow,
              CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            // Try getting first window if no main window
            var windows: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success,
               let windowsArray = windows as? [AXUIElement],
               let firstWindow = windowsArray.first {
                return firstWindow
            }
            return nil
        }
        
        return (windowRef as! AXUIElement)
    }
    
    /// Activate an app and show its main window
    static func activateAndShowMainWindow(bundleIdentifier: String) -> Bool {
        // First, activate the app
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running, cannot activate")
            return false
        }
        
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        if !activated {
            // Try AppleScript as fallback
            let script = """
            tell application id "\(bundleIdentifier)"
                activate
            end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    Logger.log("WindowManager: Failed to activate app \(bundleIdentifier)")
                    return false
                }
            }
        }
        
        // Wait a moment for app to activate, then show main window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let mainWindow = getMainWindow(bundleIdentifier: bundleIdentifier) {
                var position: CFTypeRef?
                if AXUIElementCopyAttributeValue(mainWindow, kAXPositionAttribute as CFString, &position) == .success {
                    // Window exists, try to bring it forward
                    let frontmost: CFBoolean = kCFBooleanTrue
                    AXUIElementSetAttributeValue(mainWindow, kAXFrontmostAttribute as CFString, frontmost)
                }
            }
        }
        
        Logger.log("WindowManager: Activated app \(bundleIdentifier) and showing main window")
        return true
    }
    
    /// Quit an app gracefully
    static func quitApp(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running, cannot quit")
            return false
        }
        let success = app.terminate()
        if !success {
            Logger.log("WindowManager: terminate() returned false for \(bundleIdentifier), attempting forceTerminate")
            app.forceTerminate()
        }
        Logger.log("WindowManager: Requested quit for \(bundleIdentifier)")
        return true
    }
    
    /// Bring all windows of an app to the front (without minimizing/restore)
    static func bringAllToFront(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running")
            return false
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            Logger.log("WindowManager: No windows to bring front for \(bundleIdentifier)")
            return false
        }
        
        var raisedCount = 0
        for window in windows {
            if AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success {
                raisedCount += 1
            }
        }
        
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        if !activated {
            let script = """
            tell application id "\(bundleIdentifier)"
                activate
            end tell
            """
            _ = runAppleScript(script, context: "BringAllToFront activate \(bundleIdentifier)")
        }
        
        Logger.log("WindowManager: Raised \(raisedCount) windows for \(bundleIdentifier)")
        return raisedCount > 0
    }
    
    /// Hide all other apps except the provided bundle
    static func hideOthers(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            Logger.log("WindowManager: App \(bundleIdentifier) is not running")
            return false
        }
        
        // Activate target app first (and unhide if needed)
        if app.isHidden {
            app.unhide()
        }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        
        let script = """
        tell application "System Events"
            keystroke "h" using {command down, option down}
        end tell
        """
        let success = runAppleScript(script, context: "HideOthers")
        Logger.log("WindowManager: Hide others invoked for \(bundleIdentifier); success=\(success)")
        return success
    }
    
    /// Show all apps (inverse of Hide Others)
    static func showAllApplications() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var changed = false
        for app in apps {
            if app.isHidden {
                app.unhide()
                changed = true
            }
        }
        
        if changed {
            Logger.log("WindowManager: Show All - unhid applications")
            return true
        }
        
        // Fallback to AppleScript "Show All" in case app states are inconsistent
        let script = """
        tell application "System Events"
            try
                keystroke "h" using {command down, option down, shift down}
            end try
        end tell
        """
        let success = runAppleScript(script, context: "ShowAll")
        Logger.log("WindowManager: Show All fallback via AppleScript; success=\(success)")
        return success
    }
    
    /// Check if any other app (excluding the provided bundle) is currently hidden.
    static func anyHiddenOthers(excluding bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return id != bundleIdentifier && $0.isHidden
        }
    }
    
    @discardableResult
    private static func runAppleScript(_ source: String, context: String) -> Bool {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            appleScript.executeAndReturnError(&error)
            if let error {
                Logger.log("WindowManager: AppleScript error (\(context)): \(error)")
                return false
            }
            return true
        }
        Logger.log("WindowManager: AppleScript creation failed (\(context))")
        return false
    }
}

