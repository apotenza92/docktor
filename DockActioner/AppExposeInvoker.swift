import AppKit
import Carbon
import os.log

struct HotKey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Resolves the user's configured "Application windows" shortcut and synthesizes it.
/// Falls back to Control+Down when the shortcut cannot be resolved.
final class AppExposeInvoker {
    private let applicationWindowsHotKeyId: Int32 = 33

    func invokeApplicationWindows(for bundle: String) {
        Logger.log("AppExposeInvoker: invokeApplicationWindows called for bundle \(bundle)")
        let hotKey = resolveHotKey() ?? HotKey(keyCode: 125, flags: [.maskControl])
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        Logger.log("AppExposeInvoker: frontmost before send: \(frontmost), using keyCode \(hotKey.keyCode) flags \(hotKey.flags.rawValue) for \(bundle)")
        Logger.log("AppExposeInvoker: About to send hotkey via CGEvent and AppleScript")
        send(hotKey: hotKey)
        Logger.log("AppExposeInvoker: Hotkey send completed")
    }

    private func resolveHotKey() -> HotKey? {
        guard let prefs = loadSymbolicHotKeys() else {
            Logger.log("AppExposeInvoker: Symbolic hotkey prefs unavailable; falling back to Ctrl+Down.")
            return nil
        }

        Logger.log("AppExposeInvoker: Symbolic hotkey keys found: \(Array(prefs.keys))")

        guard let entry = prefs[String(applicationWindowsHotKeyId)] as? [String: Any] else {
            Logger.log("AppExposeInvoker: No entry for id \(applicationWindowsHotKeyId); attempting fallback scan.")
            return resolveFallbackHotKey(from: prefs)
        }

        guard let enabled = entry["enabled"] as? Bool, enabled else {
            Logger.log("AppExposeInvoker: App Exposé hotkey disabled in prefs; falling back to Ctrl+Down.")
            return nil
        }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count >= 2
        else {
            Logger.log("AppExposeInvoker: App Exposé hotkey entry malformed; falling back to Ctrl+Down. Entry: \(entry)")
            return nil
        }

        let keyCode = parameters[0]
        let modifiers = parameters[1]
        let type = parameters.count > 2 ? parameters[2] : -1
        let flags = cgEventFlags(fromModifiers: modifiers)
        Logger.log("AppExposeInvoker: Resolved user hotkey: keyCode \(keyCode) modifiers \(modifiers) type \(type) flags \(flags.rawValue)")
        return HotKey(keyCode: CGKeyCode(keyCode), flags: flags)
    }

    /// If id 33 is missing, scan all entries for an enabled shortcut matching
    /// Control+Down (the common App Exposé default) and use the first match.
    private func resolveFallbackHotKey(from prefs: [String: Any]) -> HotKey? {
        for (key, value) in prefs {
            guard let entry = value as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, enabled,
                  let val = entry["value"] as? [String: Any],
                  let parameters = val["parameters"] as? [Int],
                  parameters.count >= 2
            else { continue }

            let keyCode = parameters[0]
            let modifiers = parameters[1]
            let flags = cgEventFlags(fromModifiers: modifiers)
            // Look for down arrow with control (common App Exposé binding)
            if keyCode == 125 && flags.contains(.maskControl) {
                Logger.log("AppExposeInvoker: Using fallback entry id \(key) for Control+Down: keyCode \(keyCode) modifiers \(modifiers) flags \(flags.rawValue)")
                return HotKey(keyCode: CGKeyCode(keyCode), flags: flags)
            }
        }
        Logger.log("AppExposeInvoker: No matching fallback entry for Control+Down found; will use hardcoded fallback.")
        return nil
    }

    private func loadSymbolicHotKeys() -> [String: Any]? {
        // Primary: CFPreferences (current user, any host)
        if let prefs = CFPreferencesCopyValue("AppleSymbolicHotKeys" as CFString,
                                              "com.apple.symbolichotkeys" as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? [String: Any] {
            Logger.log("AppExposeInvoker: Loaded AppleSymbolicHotKeys via CFPreferences anyHost (count \(prefs.count)).")
            return prefs
        } else {
            Logger.log("AppExposeInvoker: CFPreferences anyHost returned nil.")
        }

        // Secondary: CFPreferences current host (in case settings are host-specific)
        if let prefs = CFPreferencesCopyValue("AppleSymbolicHotKeys" as CFString,
                                              "com.apple.symbolichotkeys" as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesCurrentHost) as? [String: Any] {
            Logger.log("AppExposeInvoker: Loaded AppleSymbolicHotKeys via CFPreferences currentHost (count \(prefs.count)).")
            return prefs
        } else {
            Logger.log("AppExposeInvoker: CFPreferences currentHost returned nil.")
        }

        // Third: direct plist in Preferences
        let prefsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
        if let prefs = readPlistDict(at: prefsURL) {
            Logger.log("AppExposeInvoker: Loaded AppleSymbolicHotKeys from \(prefsURL.path) (count \(prefs.count)).")
            return prefs
        } else {
            let exists = FileManager.default.fileExists(atPath: prefsURL.path)
            Logger.log("AppExposeInvoker: \(prefsURL.path) exists: \(exists), but read failed.")
        }

        // Fourth: ByHost plist (some setups may store per-host variants)
        if let byHostURL = firstByHostSymbolicHotkeysPlist() {
            if let prefs = readPlistDict(at: byHostURL) {
                Logger.log("AppExposeInvoker: Loaded AppleSymbolicHotKeys from \(byHostURL.path) (count \(prefs.count)).")
                return prefs
            } else {
                Logger.log("AppExposeInvoker: ByHost plist read failed at \(byHostURL.path).")
            }
        } else {
            Logger.log("AppExposeInvoker: No ByHost symbolic hotkeys plist found.")
        }

        Logger.log("AppExposeInvoker: Failed to read AppleSymbolicHotKeys from any source.")
        return nil
    }

    private func readPlistDict(at url: URL) -> [String: Any]? {
        if let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = plist as? [String: Any],
           let prefs = dict["AppleSymbolicHotKeys"] as? [String: Any] {
            return prefs
        }
        return nil
    }

    private func firstByHostSymbolicHotkeysPlist() -> URL? {
        let byHostDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/ByHost")
        if let contents = try? FileManager.default.contentsOfDirectory(at: byHostDir, includingPropertiesForKeys: nil) {
            return contents.first(where: { $0.lastPathComponent.hasPrefix("com.apple.symbolichotkeys.") && $0.pathExtension == "plist" })
        }
        return nil
    }

    private func send(hotKey: HotKey) {
        Logger.log("AppExposeInvoker: send() called - sending via both CGEvent and AppleScript")
        sendViaCGEvent(hotKey: hotKey)
        sendViaAppleScript(hotKey: hotKey)
        Logger.log("AppExposeInvoker: send() completed - both methods called")
    }

    private func sendViaCGEvent(hotKey: HotKey) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Logger.log("AppExposeInvoker: Failed to create CGEventSource; cannot send hotkey.")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: hotKey.keyCode, keyDown: true)
        keyDown?.flags = hotKey.flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: hotKey.keyCode, keyDown: false)
        keyUp?.flags = hotKey.flags

        keyDown?.post(tap: .cghidEventTap)
        // Small delay to mimic real key press.
        usleep(10_000)
        keyUp?.post(tap: .cghidEventTap)

        Logger.log("AppExposeInvoker: Posted hotkey keyCode \(hotKey.keyCode) flags \(hotKey.flags.rawValue).")
    }

    private func sendViaAppleScript(hotKey: HotKey) {
        // Try a second path via System Events as a belt-and-suspenders.
        let modifiers = appleScriptModifiers(from: hotKey.flags)
        let script = """
        tell application "System Events"
            key code \(hotKey.keyCode) \(modifiers.isEmpty ? "" : "using {\(modifiers.joined(separator: ", "))}" )
        end tell
        """
        Logger.log("AppExposeInvoker: AppleScript attempting keyCode \(hotKey.keyCode) with modifiers \(modifiers). Script: \(script)")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                Logger.log("AppExposeInvoker: AppleScript send failed: \(error)")
            } else {
                Logger.log("AppExposeInvoker: AppleScript sent keyCode \(hotKey.keyCode) with modifiers \(modifiers).")
            }
        } else {
            Logger.log("AppExposeInvoker: Failed to create AppleScript for send.")
        }
    }

    private func appleScriptModifiers(from flags: CGEventFlags) -> [String] {
        var mods: [String] = []
        if flags.contains(.maskControl) { mods.append("control down") }
        if flags.contains(.maskCommand) { mods.append("command down") }
        if flags.contains(.maskShift) { mods.append("shift down") }
        if flags.contains(.maskAlternate) { mods.append("option down") }
        if flags.contains(.maskSecondaryFn) { mods.append("function down") }
        return mods
    }

    private func cgEventFlags(fromModifiers modifiers: Int) -> CGEventFlags {
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var flags = CGEventFlags()
        if nsFlags.contains(.shift) { flags.insert(.maskShift) }
        if nsFlags.contains(.control) { flags.insert(.maskControl) }
        if nsFlags.contains(.option) { flags.insert(.maskAlternate) }
        if nsFlags.contains(.command) { flags.insert(.maskCommand) }
        if nsFlags.contains(.function) { flags.insert(.maskSecondaryFn) }
        if nsFlags.contains(.numericPad) { flags.insert(.maskNumericPad) }
        if nsFlags.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }
}

