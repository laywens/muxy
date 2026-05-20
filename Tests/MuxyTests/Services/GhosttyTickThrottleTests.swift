import Foundation
import Testing

@testable import Muxy

@Suite("GhosttyTickThrottle")
struct GhosttyTickThrottleTests {
    @Test("visible surfaces tick immediately")
    func visibleSurfacesTickImmediately() {
        let throttle = GhosttyTickThrottle(minimumOccludedInterval: 0.5)
        let now = Date(timeIntervalSince1970: 10)

        let decision = throttle.scheduleWakeup(
            liveSurfaces: 2,
            occludedSurfaces: 1,
            now: now
        )

        #expect(decision == .immediate)
        #expect(!throttle.hasPendingDeferredTick)
    }

    @Test("missing live surfaces drops wakeups")
    func missingLiveSurfacesDropsWakeups() {
        let throttle = GhosttyTickThrottle(minimumOccludedInterval: 0.5)

        let decision = throttle.scheduleWakeup(
            liveSurfaces: 0,
            occludedSurfaces: 0,
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(decision == .drop)
        #expect(!throttle.hasPendingDeferredTick)
    }

    @Test("all occluded surfaces coalesce wakeups")
    func allOccludedSurfacesCoalesceWakeups() {
        let throttle = GhosttyTickThrottle(minimumOccludedInterval: 0.5)
        let first = Date(timeIntervalSince1970: 10)

        #expect(throttle.scheduleWakeup(liveSurfaces: 2, occludedSurfaces: 2, now: first) == .immediate)

        let second = throttle.scheduleWakeup(
            liveSurfaces: 2,
            occludedSurfaces: 2,
            now: first.addingTimeInterval(0.1)
        )
        guard case let .deferred(delay) = second else {
            Issue.record("expected deferred wakeup")
            return
        }
        #expect(abs(delay - 0.4) < 0.001)
        #expect(throttle.hasPendingDeferredTick)

        let third = throttle.scheduleWakeup(
            liveSurfaces: 2,
            occludedSurfaces: 2,
            now: first.addingTimeInterval(0.2)
        )
        #expect(third == .drop)

        #expect(throttle.consumeDeferredTick(now: first.addingTimeInterval(0.5)))
        #expect(!throttle.hasPendingDeferredTick)
    }

    @Test("visible wakeup clears pending occluded tick")
    func visibleWakeupClearsPendingOccludedTick() {
        let throttle = GhosttyTickThrottle(minimumOccludedInterval: 0.5)
        let first = Date(timeIntervalSince1970: 10)

        _ = throttle.scheduleWakeup(liveSurfaces: 1, occludedSurfaces: 1, now: first)
        _ = throttle.scheduleWakeup(liveSurfaces: 1, occludedSurfaces: 1, now: first.addingTimeInterval(0.1))
        #expect(throttle.hasPendingDeferredTick)

        let visible = throttle.scheduleWakeup(
            liveSurfaces: 1,
            occludedSurfaces: 0,
            now: first.addingTimeInterval(0.2)
        )

        #expect(visible == .immediate)
        #expect(!throttle.consumeDeferredTick(now: first.addingTimeInterval(0.5)))
    }
}
