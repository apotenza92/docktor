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
    private let scrollDefaultsMigratedKey = "scrollDefaultsMigrated_v2"
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
        let clickAction: DockAction
        if let clickRaw = userDefaults.string(forKey: clickActionKey),
           let click = DockAction(rawValue: clickRaw) {
            clickAction = click
        } else {
            clickAction = .hideApp // Default: Hide App
        }
        
        var scrollUpAction: DockAction
        if let scrollUpRaw = userDefaults.string(forKey: scrollUpActionKey),
           let scrollUp = DockAction(rawValue: scrollUpRaw) {
            scrollUpAction = scrollUp
        } else {
            scrollUpAction = .appExpose // Default: App Exposé
        }
        
        var scrollDownAction: DockAction
        if let scrollDownRaw = userDefaults.string(forKey: scrollDownActionKey),
           let scrollDown = DockAction(rawValue: scrollDownRaw) {
            scrollDownAction = scrollDown
        } else {
            scrollDownAction = .minimizeAll // Default: Minimize All
        }
        
        // One-time migration to flip legacy defaults (minimizeAll up / appExpose down) to new defaults.
        let migrated = userDefaults.bool(forKey: scrollDefaultsMigratedKey)
        if !migrated {
            if scrollUpAction == .minimizeAll && scrollDownAction == .appExpose {
                scrollUpAction = .appExpose
                scrollDownAction = .minimizeAll
                userDefaults.set(scrollUpAction.rawValue, forKey: scrollUpActionKey)
                userDefaults.set(scrollDownAction.rawValue, forKey: scrollDownActionKey)
            }
            userDefaults.set(true, forKey: scrollDefaultsMigratedKey)
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

