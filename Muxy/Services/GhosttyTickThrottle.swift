import Foundation

enum GhosttyTickDecision: Equatable {
    case immediate
    case deferred(TimeInterval)
    case drop
}

final class GhosttyTickThrottle {
    private let minimumOccludedInterval: TimeInterval
    private var lastOccludedTickAt: Date?
    private(set) var hasPendingDeferredTick = false

    init(minimumOccludedInterval: TimeInterval = 0.5) {
        self.minimumOccludedInterval = minimumOccludedInterval
    }

    func scheduleWakeup(
        liveSurfaces: Int,
        occludedSurfaces: Int,
        now: Date = Date()
    ) -> GhosttyTickDecision {
        guard liveSurfaces > 0 else {
            hasPendingDeferredTick = false
            return .drop
        }

        guard occludedSurfaces >= liveSurfaces else {
            hasPendingDeferredTick = false
            return .immediate
        }

        guard let lastOccludedTickAt else {
            self.lastOccludedTickAt = now
            return .immediate
        }

        let elapsed = now.timeIntervalSince(lastOccludedTickAt)
        guard elapsed < minimumOccludedInterval else {
            self.lastOccludedTickAt = now
            hasPendingDeferredTick = false
            return .immediate
        }

        guard !hasPendingDeferredTick else { return .drop }
        hasPendingDeferredTick = true
        return .deferred(minimumOccludedInterval - elapsed)
    }

    func consumeDeferredTick(now: Date = Date()) -> Bool {
        guard hasPendingDeferredTick else { return false }
        hasPendingDeferredTick = false
        lastOccludedTickAt = now
        return true
    }
}
