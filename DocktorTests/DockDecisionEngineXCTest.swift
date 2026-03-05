import XCTest

final class DockDecisionEngineXCTest: XCTestCase {
    func testAppExposeInteractionActiveWithInvocationToken() {
        XCTAssertTrue(
            DockDecisionEngine.isAppExposeInteractionActive(
                hasInvocationToken: true,
                frontmostBefore: nil,
                hasTrackingState: false,
                isRecentInteraction: false
            )
        )
    }

    func testAppExposeInteractionActiveWhenDockFrontmostAndTracked() {
        XCTAssertTrue(
            DockDecisionEngine.isAppExposeInteractionActive(
                hasInvocationToken: false,
                frontmostBefore: "com.apple.dock",
                hasTrackingState: true,
                isRecentInteraction: true
            )
        )
    }

    func testFirstClickAppExposeGate() {
        XCTAssertFalse(DockDecisionEngine.shouldRunFirstClickAppExpose(windowCount: 0, requiresMultipleWindows: false))
        XCTAssertFalse(DockDecisionEngine.shouldRunFirstClickAppExpose(windowCount: 1, requiresMultipleWindows: true))
        XCTAssertTrue(DockDecisionEngine.shouldRunFirstClickAppExpose(windowCount: 2, requiresMultipleWindows: true))
    }

    func testAppExposeInvocationConfirmationRules() {
        XCTAssertFalse(
            DockDecisionEngine.appExposeInvocationConfirmed(
                dispatched: false,
                evidence: true,
                requireEvidence: true
            )
        )
        XCTAssertFalse(
            DockDecisionEngine.appExposeInvocationConfirmed(
                dispatched: true,
                evidence: false,
                requireEvidence: true
            )
        )
        XCTAssertTrue(
            DockDecisionEngine.appExposeInvocationConfirmed(
                dispatched: true,
                evidence: true,
                requireEvidence: true
            )
        )
        XCTAssertTrue(
            DockDecisionEngine.appExposeInvocationConfirmed(
                dispatched: true,
                evidence: false,
                requireEvidence: false
            )
        )
    }

    func testExposeTrackingCommitDecision() {
        XCTAssertTrue(DockDecisionEngine.shouldCommitAppExposeTracking(invocationConfirmed: true))
        XCTAssertFalse(DockDecisionEngine.shouldCommitAppExposeTracking(invocationConfirmed: false))
    }

    func testPlainFirstClickConsumeBehavior() {
        XCTAssertFalse(
            DockDecisionEngine.shouldConsumeFirstClickPlainAction(
                firstClickBehavior: .activateApp,
                isRunning: true,
                windowCount: 2
            )
        )

        XCTAssertTrue(
            DockDecisionEngine.shouldConsumeFirstClickPlainAction(
                firstClickBehavior: .bringAllToFront,
                isRunning: true,
                windowCount: 2
            )
        )

        XCTAssertFalse(
            DockDecisionEngine.shouldConsumeFirstClickPlainAction(
                firstClickBehavior: .appExpose,
                isRunning: true,
                windowCount: 2
            )
        )
    }

    func testScrollDirectionResolutionUsesEventDeltaSign() {
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDirection(delta: 1),
            .up
        )
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDirection(delta: -1),
            .down
        )
    }

    func testEffectiveScrollDeltaCanFlipDiscreteDirectionOnly() {
        XCTAssertEqual(
            DockDecisionEngine.effectiveScrollDelta(
                delta: 3,
                isContinuous: false,
                invertDiscreteDirection: false
            ),
            3
        )

        XCTAssertEqual(
            DockDecisionEngine.effectiveScrollDelta(
                delta: 3,
                isContinuous: false,
                invertDiscreteDirection: true
            ),
            -3
        )

        XCTAssertEqual(
            DockDecisionEngine.effectiveScrollDelta(
                delta: 3,
                isContinuous: true,
                invertDiscreteDirection: true
            ),
            3
        )
    }

    func testAutoDiscreteInvertHeuristic() {
        XCTAssertFalse(
            DockDecisionEngine.shouldInvertDiscreteScrollDirection(
                isContinuous: true,
                sourceBundleIdentifier: "com.caldis.Mos",
                knownRemapperRunning: true,
                userOverride: false
            )
        )

        XCTAssertTrue(
            DockDecisionEngine.shouldInvertDiscreteScrollDirection(
                isContinuous: false,
                sourceBundleIdentifier: nil,
                knownRemapperRunning: false,
                userOverride: true
            )
        )

        XCTAssertTrue(
            DockDecisionEngine.shouldInvertDiscreteScrollDirection(
                isContinuous: false,
                sourceBundleIdentifier: "com.caldis.Mos",
                knownRemapperRunning: false,
                userOverride: false
            )
        )

        XCTAssertTrue(
            DockDecisionEngine.shouldInvertDiscreteScrollDirection(
                isContinuous: false,
                sourceBundleIdentifier: nil,
                knownRemapperRunning: true,
                userOverride: false
            )
        )

        XCTAssertFalse(
            DockDecisionEngine.shouldInvertDiscreteScrollDirection(
                isContinuous: false,
                sourceBundleIdentifier: nil,
                knownRemapperRunning: false,
                userOverride: false
            )
        )
    }

    func testResolvedScrollDeltaPrefersAppKitInterpretedDeltaWhenAvailable() {
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDelta(
                pointDelta: -8,
                fixedDelta: -1,
                coarseDelta: 1,
                appKitDelta: 6,
                isContinuous: false
            ),
            6
        )
    }

    func testResolvedScrollDeltaPrefersPointForContinuousDevices() {
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDelta(
                pointDelta: -8,
                fixedDelta: -1,
                coarseDelta: 1,
                appKitDelta: 0,
                isContinuous: true
            ),
            -8
        )
    }

    func testResolvedScrollDeltaUsesMajoritySignForDiscreteWheelConflicts() {
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDelta(
                pointDelta: 12,
                fixedDelta: 1,
                coarseDelta: -1,
                appKitDelta: 0,
                isContinuous: false
            ),
            12
        )
    }

    func testResolvedScrollDeltaFallsBackWhenNoMajorityForDiscreteWheel() {
        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDelta(
                pointDelta: -8,
                fixedDelta: 0,
                coarseDelta: 1,
                appKitDelta: 0,
                isContinuous: false
            ),
            1
        )

        XCTAssertEqual(
            DockDecisionEngine.resolvedScrollDelta(
                pointDelta: 0,
                fixedDelta: 2,
                coarseDelta: 0,
                appKitDelta: 0,
                isContinuous: false
            ),
            2
        )
    }
}
