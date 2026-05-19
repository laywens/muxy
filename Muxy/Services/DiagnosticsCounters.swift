import Foundation

struct DiagnosticsCounterSnapshot: Equatable {
    let mainThreadStalls: Int
    let mainThreadStallTotalMS: Int
    let mainThreadStallMaxMS: Int
    let ghosttyWakeups: Int
    let ghosttyTicks: Int
    let liveSurfaces: Int
    let occludedSurfaces: Int
    let branchObservers: Int
    let fseventStreamsActive: Int
    let fseventStreamsCreated: Int
    let fseventStreamsStopped: Int
    let fseventEvents: Int
    let watcherRefreshes: Int
    let subprocessActive: Int
    let subprocessStarted: Int
    let subprocessCompleted: Int
    let subprocessTimedOut: Int
    let subprocessTotalDurationMS: Int
    let subprocessMaxDurationMS: Int
    let remoteStreamingBytes: Int
}

final class DiagnosticsCounters: @unchecked Sendable {
    static let shared = DiagnosticsCounters()

    private let lock = NSLock()
    private var state = State()

    init() {}

    func recordMainThreadStall(duration: TimeInterval) {
        lock.withLock {
            let ms = Self.milliseconds(duration)
            state.mainThreadStalls += 1
            state.mainThreadStallTotalMS += ms
            state.mainThreadStallMaxMS = max(state.mainThreadStallMaxMS, ms)
        }
    }

    func recordGhosttyWakeup() {
        lock.withLock {
            state.ghosttyWakeups += 1
        }
    }

    func recordGhosttyTick() {
        lock.withLock {
            state.ghosttyTicks += 1
        }
    }

    func setSurfaceCounts(live: Int, occluded: Int) {
        lock.withLock {
            state.liveSurfaces = max(0, live)
            state.occludedSurfaces = max(0, occluded)
        }
    }

    func setBranchObserverCount(_ count: Int) {
        lock.withLock {
            state.branchObservers = max(0, count)
        }
    }

    func recordFSEventStreamStarted() {
        lock.withLock {
            state.fseventStreamsActive += 1
            state.fseventStreamsCreated += 1
        }
    }

    func recordFSEventStreamStopped() {
        lock.withLock {
            state.fseventStreamsActive = max(0, state.fseventStreamsActive - 1)
            state.fseventStreamsStopped += 1
        }
    }

    func recordFSEvents(eventCount: Int) {
        guard eventCount > 0 else { return }
        lock.withLock {
            state.fseventEvents += eventCount
        }
    }

    func recordWatcherRefresh() {
        lock.withLock {
            state.watcherRefreshes += 1
        }
    }

    func recordSubprocessStarted() {
        lock.withLock {
            state.subprocessActive += 1
            state.subprocessStarted += 1
        }
    }

    func recordSubprocessFinished(duration: TimeInterval, timedOut: Bool) {
        lock.withLock {
            state.subprocessActive = max(0, state.subprocessActive - 1)
            state.subprocessCompleted += 1
            if timedOut {
                state.subprocessTimedOut += 1
            }
            let ms = Self.milliseconds(duration)
            state.subprocessTotalDurationMS += ms
            state.subprocessMaxDurationMS = max(state.subprocessMaxDurationMS, ms)
        }
    }

    func beginSubprocess() -> DiagnosticsSubprocessToken {
        recordSubprocessStarted()
        return DiagnosticsSubprocessToken(counters: self)
    }

    func recordRemoteTerminalBytes(_ byteCount: Int) {
        guard byteCount > 0 else { return }
        lock.withLock {
            state.remoteStreamingBytes += byteCount
        }
    }

    func snapshot() -> DiagnosticsCounterSnapshot {
        lock.withLock {
            DiagnosticsCounterSnapshot(
                mainThreadStalls: state.mainThreadStalls,
                mainThreadStallTotalMS: state.mainThreadStallTotalMS,
                mainThreadStallMaxMS: state.mainThreadStallMaxMS,
                ghosttyWakeups: state.ghosttyWakeups,
                ghosttyTicks: state.ghosttyTicks,
                liveSurfaces: state.liveSurfaces,
                occludedSurfaces: state.occludedSurfaces,
                branchObservers: state.branchObservers,
                fseventStreamsActive: state.fseventStreamsActive,
                fseventStreamsCreated: state.fseventStreamsCreated,
                fseventStreamsStopped: state.fseventStreamsStopped,
                fseventEvents: state.fseventEvents,
                watcherRefreshes: state.watcherRefreshes,
                subprocessActive: state.subprocessActive,
                subprocessStarted: state.subprocessStarted,
                subprocessCompleted: state.subprocessCompleted,
                subprocessTimedOut: state.subprocessTimedOut,
                subprocessTotalDurationMS: state.subprocessTotalDurationMS,
                subprocessMaxDurationMS: state.subprocessMaxDurationMS,
                remoteStreamingBytes: state.remoteStreamingBytes
            )
        }
    }

    func resetForTesting() {
        lock.withLock {
            state = State()
        }
    }

    private static func milliseconds(_ duration: TimeInterval) -> Int {
        max(0, Int((duration * 1000).rounded()))
    }

    private struct State {
        var mainThreadStalls = 0
        var mainThreadStallTotalMS = 0
        var mainThreadStallMaxMS = 0
        var ghosttyWakeups = 0
        var ghosttyTicks = 0
        var liveSurfaces = 0
        var occludedSurfaces = 0
        var branchObservers = 0
        var fseventStreamsActive = 0
        var fseventStreamsCreated = 0
        var fseventStreamsStopped = 0
        var fseventEvents = 0
        var watcherRefreshes = 0
        var subprocessActive = 0
        var subprocessStarted = 0
        var subprocessCompleted = 0
        var subprocessTimedOut = 0
        var subprocessTotalDurationMS = 0
        var subprocessMaxDurationMS = 0
        var remoteStreamingBytes = 0
    }
}

final class DiagnosticsSubprocessToken: @unchecked Sendable {
    private let counters: DiagnosticsCounters
    private let startedAt = Date()
    private let lock = NSLock()
    private var timedOut = false
    private var finished = false

    init(counters: DiagnosticsCounters) {
        self.counters = counters
    }

    func markTimedOut() {
        lock.withLock {
            guard !finished else { return }
            timedOut = true
        }
    }

    func finish() {
        let didTimeOut: Bool
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        didTimeOut = timedOut
        lock.unlock()

        counters.recordSubprocessFinished(
            duration: Date().timeIntervalSince(startedAt),
            timedOut: didTimeOut
        )
    }
}

final class DiagnosticsSubprocessTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: DiagnosticsSubprocessToken?

    func set(_ token: DiagnosticsSubprocessToken) {
        lock.withLock {
            self.token = token
        }
    }

    func finish() {
        let token = lock.withLock {
            let token = self.token
            self.token = nil
            return token
        }
        token?.finish()
    }
}
