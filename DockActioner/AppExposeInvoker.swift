import AppKit
import Darwin

struct HotKey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

enum AppExposeInvokeStrategy: String {
    case dockNotification = "dockNotification"
    case resolvedHotKey = "resolvedHotKey"
    case fallbackControlDown = "fallbackControlDown"
}

/// Triggers App Expose using Dock private notification.
final class AppExposeInvoker {
    private let appExposeDockNotification = "com.apple.expose.front.awake"

    // Diagnostics kept for UI/test compatibility.
    private(set) var lastResolvedHotKey: HotKey?
    private(set) var lastResolveError: String?
    private(set) var lastInvokeStrategy: AppExposeInvokeStrategy?
    private(set) var lastInvokeAttempts: [String] = []
    private(set) var lastForcedStrategy: String?

    func invokeApplicationWindows(for bundle: String) {
        Logger.log("AppExposeInvoker: invokeApplicationWindows called for bundle \(bundle)")

        lastResolvedHotKey = nil
        lastResolveError = "not-applicable (dock notification path)"
        lastInvokeStrategy = nil
        lastInvokeAttempts = []
        lastForcedStrategy = ProcessInfo.processInfo.environment["DOCKACTIONER_APPEXPOSE_STRATEGY"]

        if let forced = lastForcedStrategy, !forced.isEmpty {
            Logger.log("AppExposeInvoker: DOCKACTIONER_APPEXPOSE_STRATEGY=\(forced) ignored (docknotify-only mode)")
        }

        let posted = DockNotificationSender.post(notification: appExposeDockNotification)
        recordAttempt("dockNotification=\(posted)")
        Logger.log("AppExposeInvoker: attempt=dockNotification(\(appExposeDockNotification)) posted=\(posted)")

        if posted {
            lastInvokeStrategy = .dockNotification
            Logger.log("AppExposeInvoker: selected strategy=dockNotification")
        } else {
            lastResolveError = "CoreDockSendNotification unavailable"
            Logger.log("AppExposeInvoker: failed - CoreDockSendNotification unavailable")
        }
    }

    func isApplicationWindowsHotKeyConfigured() -> Bool {
        isDockNotificationAvailable()
    }

    func isDockNotificationAvailable() -> Bool {
        DockNotificationSender.isAvailable
    }

    private func recordAttempt(_ attempt: String) {
        lastInvokeAttempts.append(attempt)
    }
}

private enum DockNotificationSender {
    private typealias CoreDockSendNotificationFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    private static let fn: CoreDockSendNotificationFn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            Logger.log("DockNotificationSender: CoreDockSendNotification symbol unavailable")
            return nil
        }
        return unsafeBitCast(symbol, to: CoreDockSendNotificationFn.self)
    }()

    static var isAvailable: Bool {
        fn != nil
    }

    static func post(notification: String) -> Bool {
        guard let fn else { return false }
        fn(notification as CFString, nil)
        return true
    }
}
