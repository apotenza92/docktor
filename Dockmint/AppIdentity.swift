import Foundation

enum AppIdentity {
    static let transitionStableBundleIdentifier = "pzc.Dockter"
    static let transitionBetaBundleIdentifier = "pzc.Dockter.beta"
    static let cleanupStableBundleIdentifier = "pzc.Dockmint"
    static let cleanupBetaBundleIdentifier = "pzc.Dockmint.beta"

    static let stableBundleName = "Dockmint.app"
    static let betaBundleName = "Dockmint Beta.app"

    static let legacyAppBundleNames: Set<String> = [
        "DockActioner.app",
        "Dockter.app",
        "Docktor.app",
        "Docktor Beta.app",
    ]

    static let familyAppNames: Set<String> = [
        "Dockmint",
        "Dockmint Beta",
        "Docktor",
        "Docktor Beta",
        "Dockter",
        "DockActioner",
    ]

    static let familyBundleIdentifiers: Set<String> = [
        transitionStableBundleIdentifier,
        transitionBetaBundleIdentifier,
        cleanupStableBundleIdentifier,
        cleanupBetaBundleIdentifier,
    ]

    static let currentURLScheme = "dockmint"
    static let legacyURLSchemes: Set<String> = ["docktor", "dockter"]
    static let currentOpenSettingsNotification = Notification.Name("pzc.Dockmint.openSettings")
    static let legacyOpenSettingsNotification = Notification.Name("pzc.Docktor.openSettings")

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    static var isBetaBuild: Bool {
        bundleIdentifier.hasSuffix(".beta")
    }

    static var usesTransitionBundleIdentifier: Bool {
        bundleIdentifier == transitionStableBundleIdentifier || bundleIdentifier == transitionBetaBundleIdentifier
    }

    static var usesCleanupBundleIdentifier: Bool {
        bundleIdentifier == cleanupStableBundleIdentifier || bundleIdentifier == cleanupBetaBundleIdentifier
    }

    static var currentAppBundleName: String {
        isBetaBuild ? betaBundleName : stableBundleName
    }

    static var preferredFeedRepository: String {
        usesTransitionBundleIdentifier ? "apotenza92/docktor" : "apotenza92/dockmint"
    }

    static var preferredFeedBaseURL: String {
        "https://raw.githubusercontent.com/\(preferredFeedRepository)/main/appcasts"
    }

    static var settingsNotificationNames: [Notification.Name] {
        [currentOpenSettingsNotification, legacyOpenSettingsNotification]
    }

    static func acceptsURLScheme(_ scheme: String) -> Bool {
        let lowered = scheme.lowercased()
        return lowered == currentURLScheme || legacyURLSchemes.contains(lowered)
    }

    static func flagValue(primary: String, legacy: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let value = environment[primary], !value.isEmpty {
            return value
        }
        guard let legacy, let value = environment[legacy], !value.isEmpty else {
            return nil
        }
        return value
    }

    static func boolFlag(primary: String, legacy: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = flagValue(primary: primary, legacy: legacy, environment: environment)?.lowercased() else {
            return false
        }
        return value == "1" || value == "true" || value == "yes"
    }

    static var oldLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Code/Docktor/logs")
    }

    static var newLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Code/Dockmint/logs")
    }
}
