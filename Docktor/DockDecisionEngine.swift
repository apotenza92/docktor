import Foundation

enum DecisionFirstClickBehavior {
    case activateApp
    case bringAllToFront
    case appExpose
}

enum DecisionDockAction {
    case none
    case activateApp
    case hideApp
    case appExpose
    case minimizeAll
    case quitApp
    case bringAllToFront
    case hideOthers
    case singleAppMode
}

enum DecisionScrollDirection: Equatable {
    case up
    case down
}

enum DockDecisionEngine {
    static func isAppExposeInteractionActive(hasInvocationToken: Bool,
                                             frontmostBefore: String?,
                                             hasTrackingState: Bool,
                                             isRecentInteraction: Bool) -> Bool {
        if hasInvocationToken {
            return true
        }

        return frontmostBefore == "com.apple.dock" && hasTrackingState && isRecentInteraction
    }

    static func appExposeInvocationConfirmed(dispatched: Bool,
                                             evidence: Bool,
                                             requireEvidence: Bool) -> Bool {
        if requireEvidence {
            return dispatched && evidence
        }
        return dispatched
    }

    static func shouldCommitAppExposeTracking(invocationConfirmed: Bool) -> Bool {
        invocationConfirmed
    }

    static func shouldRunFirstClickAppExpose(windowCount: Int,
                                             requiresMultipleWindows: Bool) -> Bool {
        guard windowCount > 0 else { return false }
        if requiresMultipleWindows && windowCount < 2 {
            return false
        }
        return true
    }

    static func shouldConsumeFirstClickPlainAction(firstClickBehavior: DecisionFirstClickBehavior,
                                                   isRunning: Bool,
                                                   windowCount: Int) -> Bool {
        switch firstClickBehavior {
        case .activateApp:
            return false
        case .bringAllToFront:
            return isRunning
        case .appExpose:
            guard isRunning else { return false }
            // App Exposé should stay pass-through to preserve Dock click semantics.
            if windowCount == 0 {
                return false
            }
            return false
        }
    }

    static func shouldConsumeFirstClickModifierAction(action: DecisionDockAction,
                                                      isRunning: Bool,
                                                      canRunAppExpose: Bool) -> Bool {
        guard isRunning else { return false }

        switch action {
        case .none:
            return false
        case .appExpose:
            _ = canRunAppExpose
            return false
        default:
            return true
        }
    }

    static func resolvedScrollDelta(pointDelta: Double,
                                    fixedDelta: Double,
                                    coarseDelta: Double,
                                    appKitDelta: Double,
                                    isContinuous: Bool) -> Double {
        // Prefer AppKit's interpreted delta when available. It represents how regular macOS
        // apps see the scroll event after system/device policy and upstream transforms.
        if appKitDelta != 0 {
            return appKitDelta
        }

        if isContinuous {
            // Trackpad/magic mouse: point deltas are the most expressive signal.
            return [pointDelta, fixedDelta, coarseDelta].first(where: { $0 != 0 }) ?? 0
        }

        // Discrete wheel devices can have remappers that rewrite only a subset of fields.
        // If at least two fields agree on sign, follow that majority sign.
        let fields = [pointDelta, fixedDelta, coarseDelta].filter { $0 != 0 }
        let positiveCount = fields.filter { $0 > 0 }.count
        let negativeCount = fields.filter { $0 < 0 }.count

        if positiveCount >= 2 || negativeCount >= 2 {
            let majorityPositive = positiveCount > negativeCount
            let matching = fields.filter { majorityPositive ? ($0 > 0) : ($0 < 0) }
            if let strongest = matching.max(by: { abs($0) < abs($1) }) {
                return strongest
            }
        }

        // Tie/unknown fallback: fixed-point, then coarse notch, then point.
        return [fixedDelta, coarseDelta, pointDelta].first(where: { $0 != 0 }) ?? 0
    }

    private static let knownRemapperHints: [String] = [
        "com.caldis.mos",
        "com.lujjjh.linearmouse",
        "linearmouse",
        "mos",
        "unnaturalscrollwheels",
    ]

    static func shouldInvertDiscreteScrollDirection(isContinuous: Bool,
                                                    sourceBundleIdentifier: String?,
                                                    knownRemapperRunning: Bool,
                                                    userOverride: Bool) -> Bool {
        guard !isContinuous else { return false }
        if userOverride { return true }

        if let source = sourceBundleIdentifier?.lowercased(),
           knownRemapperHints.contains(where: { source.contains($0) }) {
            return true
        }

        return knownRemapperRunning
    }

    static func effectiveScrollDelta(delta: Double,
                                     isContinuous: Bool,
                                     invertDiscreteDirection: Bool) -> Double {
        guard !isContinuous, invertDiscreteDirection else { return delta }
        return -delta
    }

    static func resolvedScrollDirection(delta: Double) -> DecisionScrollDirection {
        return delta > 0 ? .up : .down
    }
}
