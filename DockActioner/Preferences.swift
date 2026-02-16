import Foundation
import Combine
import ServiceManagement

enum DockAction: String, CaseIterable, Codable {
    case hideApp = "hideApp"
    case appExpose = "appExpose"
    case minimizeAll = "minimizeAll"
    case quitApp = "quitApp"
    case bringAllToFront = "bringAllToFront"
    case hideOthers = "hideOthers"
    
    var displayName: String {
        switch self {
        case .hideApp: return "Hide App"
        case .appExpose: return "App Exposé"
        case .minimizeAll: return "Minimize All"
        case .quitApp: return "Quit App"
        case .bringAllToFront: return "Bring All to Front"
        case .hideOthers: return "Hide Others"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    
    private let userDefaults = UserDefaults.standard
    private let clickActionKey = "clickAction"
    private let scrollUpActionKey = "scrollUpAction"
    private let scrollDownActionKey = "scrollDownAction"
    private let scrollDefaultsMigratedKey = "scrollDefaultsMigrated_v3"
    private let behaviorDefaultsMigratedKey = "behaviorDefaultsMigrated_v4"
    private let showOnStartupKey = "showOnStartup"
    private let firstLaunchCompletedKey = "firstLaunchCompleted"
    private let startAtLoginKey = "startAtLogin"
    
    // Prevent feedback loop when we adjust login item after a failed toggle.
    private var applyingLoginItemChange = false
    
    @Published var clickAction: DockAction {
        didSet {
            userDefaults.set(clickAction.rawValue, forKey: clickActionKey)
        }
    }
    
    @Published var scrollUpAction: DockAction {
        didSet {
            userDefaults.set(scrollUpAction.rawValue, forKey: scrollUpActionKey)
        }
    }
    
    @Published var scrollDownAction: DockAction {
        didSet {
            userDefaults.set(scrollDownAction.rawValue, forKey: scrollDownActionKey)
        }
    }
    
    @Published var showOnStartup: Bool {
        didSet {
            userDefaults.set(showOnStartup, forKey: showOnStartupKey)
        }
    }
    
    @Published var firstLaunchCompleted: Bool {
        didSet {
            userDefaults.set(firstLaunchCompleted, forKey: firstLaunchCompletedKey)
        }
    }
    
    @Published var startAtLogin: Bool {
        didSet {
            guard !applyingLoginItemChange else { return }
            applyingLoginItemChange = true
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                userDefaults.set(startAtLogin, forKey: startAtLoginKey)
            } catch {
                Logger.log("Failed to update login item state: \(error.localizedDescription)")
                // Revert to actual system state to keep UI truthful
                let enabled = SMAppService.mainApp.status == .enabled
                startAtLogin = enabled
                userDefaults.set(enabled, forKey: startAtLoginKey)
            }
            applyingLoginItemChange = false
        }
    }
    
    private init() {
        // Load from UserDefaults or use defaults into locals first
        var clickAction: DockAction
        if let clickRaw = userDefaults.string(forKey: clickActionKey),
           let click = DockAction(rawValue: clickRaw) {
            clickAction = click
        } else {
            clickAction = .appExpose // Default: App Expose
        }
        
        var scrollUpAction: DockAction
        if let scrollUpRaw = userDefaults.string(forKey: scrollUpActionKey),
           let scrollUp = DockAction(rawValue: scrollUpRaw) {
            scrollUpAction = scrollUp
        } else {
            scrollUpAction = .hideOthers // Default: Hide Others
        }
        
        var scrollDownAction: DockAction
        if let scrollDownRaw = userDefaults.string(forKey: scrollDownActionKey),
           let scrollDown = DockAction(rawValue: scrollDownRaw) {
            scrollDownAction = scrollDown
        } else {
            scrollDownAction = .hideApp // Default: Hide App
        }

        // One-time migration to move older defaults to current defaults.
        let migrated = userDefaults.bool(forKey: scrollDefaultsMigratedKey)
        if !migrated {
            // Legacy v1: minimizeAll up / appExpose down
            if scrollUpAction == .minimizeAll && scrollDownAction == .appExpose {
                scrollUpAction = .hideOthers
                scrollDownAction = .appExpose
                userDefaults.set(scrollUpAction.rawValue, forKey: scrollUpActionKey)
                userDefaults.set(scrollDownAction.rawValue, forKey: scrollDownActionKey)
            }

            // v2 default: appExpose up / minimizeAll down
            if scrollUpAction == .appExpose && scrollDownAction == .minimizeAll {
                scrollUpAction = .hideOthers
                scrollDownAction = .appExpose
                userDefaults.set(scrollUpAction.rawValue, forKey: scrollUpActionKey)
                userDefaults.set(scrollDownAction.rawValue, forKey: scrollDownActionKey)
            }

            userDefaults.set(true, forKey: scrollDefaultsMigratedKey)
        }

        // One-time migration to move prior default behavior to current defaults.
        let behaviorMigrated = userDefaults.bool(forKey: behaviorDefaultsMigratedKey)
        if !behaviorMigrated {
            let looksLikeLegacyDefaults = clickAction == .hideApp
                && scrollUpAction == .hideOthers
                && scrollDownAction == .appExpose

            if looksLikeLegacyDefaults {
                clickAction = .appExpose
                scrollDownAction = .hideApp
                userDefaults.set(clickAction.rawValue, forKey: clickActionKey)
                userDefaults.set(scrollDownAction.rawValue, forKey: scrollDownActionKey)
            }

            userDefaults.set(true, forKey: behaviorDefaultsMigratedKey)
        }
        
        // General settings defaults
        let showOnStartup = userDefaults.object(forKey: showOnStartupKey) as? Bool ?? false
        let firstLaunchCompleted = userDefaults.object(forKey: firstLaunchCompletedKey) as? Bool ?? false
        
        // Login item: prefer system status; fall back to stored preference
        let loginItemEnabled = SMAppService.mainApp.status == .enabled
        let startAtLogin: Bool
        if loginItemEnabled {
            startAtLogin = true
        } else {
            startAtLogin = userDefaults.object(forKey: startAtLoginKey) as? Bool ?? false
        }
        
        // Assign stored properties last
        self.clickAction = clickAction
        self.scrollUpAction = scrollUpAction
        self.scrollDownAction = scrollDownAction
        self.showOnStartup = showOnStartup
        self.firstLaunchCompleted = firstLaunchCompleted
        self.startAtLogin = startAtLogin
    }
}
