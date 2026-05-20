import Foundation
import Testing

@testable import Muxy

@Suite("DiagnosticsCounters")
struct DiagnosticsCountersTests {
    @Test("snapshot aggregates counters and gauges")
    func snapshotAggregatesCountersAndGauges() {
        let counters = DiagnosticsCounters()

        counters.recordMainThreadStall(duration: 1.25)
        counters.recordGhosttyWakeup()
        counters.recordGhosttyTick()
        counters.recordGhosttyTick()
        counters.setSurfaceCounts(live: 3, occluded: 1)
        counters.setBranchObserverCount(4)
        counters.recordFSEventStreamStarted()
        counters.recordFSEvents(eventCount: 7)
        counters.recordWatcherRefresh()
        counters.setRepoActivityCounts(streams: 2, roots: 2, subscribers: 5)
        counters.recordSubprocessStarted()
        counters.recordSubprocessFinished(duration: 0.25, timedOut: true)
        counters.recordRemoteTerminalBytes(2_048)

        let snapshot = counters.snapshot()

        #expect(snapshot.mainThreadStalls == 1)
        #expect(snapshot.mainThreadStallMaxMS == 1_250)
        #expect(snapshot.ghosttyWakeups == 1)
        #expect(snapshot.ghosttyTicks == 2)
        #expect(snapshot.liveSurfaces == 3)
        #expect(snapshot.occludedSurfaces == 1)
        #expect(snapshot.branchObservers == 4)
        #expect(snapshot.fseventStreamsActive == 1)
        #expect(snapshot.fseventStreamsCreated == 1)
        #expect(snapshot.fseventEvents == 7)
        #expect(snapshot.watcherRefreshes == 1)
        #expect(snapshot.repoActivityStreams == 2)
        #expect(snapshot.repoActivityRoots == 2)
        #expect(snapshot.repoActivitySubscribers == 5)
        #expect(snapshot.subprocessActive == 0)
        #expect(snapshot.subprocessStarted == 1)
        #expect(snapshot.subprocessCompleted == 1)
        #expect(snapshot.subprocessTimedOut == 1)
        #expect(snapshot.subprocessTotalDurationMS == 250)
        #expect(snapshot.remoteStreamingBytes == 2_048)
    }

    @Test("snapshot clamps active gauges when stops exceed starts")
    func snapshotClampsActiveGauges() {
        let counters = DiagnosticsCounters()

        counters.recordFSEventStreamStopped()
        counters.recordSubprocessFinished(duration: 0.1, timedOut: false)
        counters.setRepoActivityCounts(streams: -3, roots: -1, subscribers: -2)

        let snapshot = counters.snapshot()

        #expect(snapshot.fseventStreamsActive == 0)
        #expect(snapshot.subprocessActive == 0)
        #expect(snapshot.repoActivityStreams == 0)
        #expect(snapshot.repoActivityRoots == 0)
        #expect(snapshot.repoActivitySubscribers == 0)
        #expect(snapshot.fseventStreamsStopped == 1)
        #expect(snapshot.subprocessCompleted == 1)
    }

    @Test("subprocess token records timeout once")
    func subprocessTokenRecordsTimeoutOnce() {
        let counters = DiagnosticsCounters()
        let token = counters.beginSubprocess()

        token.markTimedOut()
        token.finish()
        token.finish()

        let snapshot = counters.snapshot()
        #expect(snapshot.subprocessActive == 0)
        #expect(snapshot.subprocessStarted == 1)
        #expect(snapshot.subprocessCompleted == 1)
        #expect(snapshot.subprocessTimedOut == 1)
    }

    @Test("subprocess token box ignores launch failures")
    func subprocessTokenBoxIgnoresLaunchFailures() {
        let counters = DiagnosticsCounters()
        let tokenBox = DiagnosticsSubprocessTokenBox()

        tokenBox.finish()

        let snapshot = counters.snapshot()
        #expect(snapshot.subprocessStarted == 0)
        #expect(snapshot.subprocessCompleted == 0)
    }

    @Test("timeout watcher marks token before firing callback")
    func timeoutWatcherMarksTokenBeforeFiringCallback() throws {
        let counters = DiagnosticsCounters()
        let token = counters.beginSubprocess()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]

        try process.run()
        let watcher = ProcessTimeoutWatcher.install(on: process, timeout: 0.01, diagnosticsToken: token) {
            token.finish()
        }
        process.waitUntilExit()
        watcher.cancel()

        let snapshot = counters.snapshot()
        #expect(snapshot.subprocessCompleted == 1)
        #expect(snapshot.subprocessTimedOut == 1)
    }

    @Test("formats snapshot and periodic diagnostics output")
    func formatsDiagnosticsOutput() {
        let snapshot = DiagnosticsCounterSnapshot(
            mainThreadStalls: 2,
            mainThreadStallTotalMS: 1_800,
            mainThreadStallMaxMS: 1_200,
            ghosttyWakeups: 3,
            ghosttyTicks: 4,
            liveSurfaces: 5,
            occludedSurfaces: 2,
            branchObservers: 6,
            fseventStreamsActive: 1,
            fseventStreamsCreated: 2,
            fseventStreamsStopped: 1,
            fseventEvents: 20,
            watcherRefreshes: 8,
            repoActivityStreams: 2,
            repoActivityRoots: 2,
            repoActivitySubscribers: 9,
            subprocessActive: 0,
            subprocessStarted: 7,
            subprocessCompleted: 7,
            subprocessTimedOut: 1,
            subprocessTotalDurationMS: 900,
            subprocessMaxDurationMS: 400,
            remoteStreamingBytes: 4_096
        )

        let report = MemoryDiagnostics.formatCounterReport(snapshot: snapshot)
        #expect(report.contains("Diagnostics Counters"))
        #expect(report.contains("Main Thread Stalls: 2"))
        #expect(report.contains("Ghostty: wakeups=3 ticks=4"))
        #expect(report.contains("Surfaces: live=5 occluded=2"))
        #expect(report.contains("Branch Observers: 6"))
        #expect(report.contains("FSEvents: activeStreams=1 created=2 stopped=1 events=20 refreshes=8"))
        #expect(report.contains("Repo Activity: streams=2 roots=2 subscribers=9"))
        #expect(report.contains("Subprocesses: active=0 started=7 completed=7 timedOut=1"))
        #expect(report.contains("Remote Streaming: outputBytes=4096"))

        let periodic = MemoryDiagnostics.formatCounterPeriodicParts(snapshot: snapshot)
        #expect(periodic.contains("stalls=2"))
        #expect(periodic.contains("ghosttyWakeups=3"))
        #expect(periodic.contains("ghosttyTicks=4"))
        #expect(periodic.contains("occludedSurfaces=2"))
        #expect(periodic.contains("repoActivityStreams=2"))
        #expect(periodic.contains("repoActivityRoots=2"))
        #expect(periodic.contains("repoActivitySubscribers=9"))
        #expect(periodic.contains("subprocessTimeouts=1"))
        #expect(periodic.contains("remoteBytes=4096"))
    }
}
