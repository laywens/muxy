import Foundation
import Testing

@testable import Muxy

private final class ResolverProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: [String] = []
    private var queue: [String?]?
    private var fixed: String?

    init(fixed: String? = nil) {
        self.fixed = fixed
    }

    init(queue: [String?]) {
        self.queue = queue
    }

    func record(_ path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        observed.append(path)
        if queue != nil {
            guard let queue, !queue.isEmpty else { return nil }
            let next = queue.first!
            self.queue = Array(queue.dropFirst())
            return next
        }
        return fixed
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return observed.count
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }
}

@MainActor
@Suite("PaneBranchObserver")
struct PaneBranchObserverTests {
    private static let pollInterval: Duration = .milliseconds(20)
    private static let pollTimeout: Duration = .seconds(10)

    private static func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: pollTimeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    @Test("update with nil clears the branch and skips the resolver")
    func clearOnNilPath() async {
        let probe = ResolverProbe(fixed: "main")
        let observer = PaneBranchObserver { path in probe.record(path) }
        observer.update(repoPath: "/tmp/repo")
        await Self.waitUntil { observer.branch == "main" }
        #expect(observer.branch == "main")
        #expect(probe.calls == 1)

        observer.update(repoPath: nil)
        await Self.waitUntil { observer.branch == nil }
        #expect(observer.branch == nil)
        #expect(probe.calls == 1)
    }

    @Test("changing repoPath triggers a resolver call")
    func resolveOnRepoChange() async {
        let probe = ResolverProbe(queue: ["feature/a", "feature/b"])
        let observer = PaneBranchObserver { path in probe.record(path) }
        observer.update(repoPath: "/tmp/a")
        await Self.waitUntil { observer.branch == "feature/a" }
        #expect(observer.branch == "feature/a")

        observer.update(repoPath: "/tmp/b")
        await Self.waitUntil { observer.branch == "feature/b" }
        #expect(observer.branch == "feature/b")
        #expect(probe.paths == ["/tmp/a", "/tmp/b"])
    }

    @Test("repeating the same path is a no-op")
    func sameRepoPathNoOp() async {
        let probe = ResolverProbe(fixed: "main")
        let observer = PaneBranchObserver { path in probe.record(path) }
        observer.update(repoPath: "/tmp/repo")
        await Self.waitUntil { probe.calls == 1 }
        observer.update(repoPath: "/tmp/repo")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(probe.calls == 1)
    }

    @Test("resolver returning nil yields a nil branch (e.g. detached HEAD)")
    func resolverReturnsNil() async {
        let probe = ResolverProbe(fixed: nil)
        let observer = PaneBranchObserver { path in probe.record(path) }
        observer.update(repoPath: "/tmp/detached")
        await Self.waitUntil { probe.calls == 1 }
        #expect(observer.branch == nil)
    }

    @Test("manual refresh re-queries the resolver")
    func manualRefresh() async {
        let probe = ResolverProbe(queue: ["one", "two"])
        let observer = PaneBranchObserver { path in probe.record(path) }
        observer.update(repoPath: "/tmp/repo")
        await Self.waitUntil { observer.branch == "one" }
        #expect(observer.branch == "one")

        observer.refresh()
        await Self.waitUntil { observer.branch == "two" }
        #expect(observer.branch == "two")
    }
}

@MainActor
@Suite("RepoBranchService")
struct RepoBranchServiceTests {
    private static let pollInterval: Duration = .milliseconds(20)
    private static let pollTimeout: Duration = .milliseconds(2000)

    private static func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: pollTimeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    @Test("canonical paths share one poller")
    func canonicalPathsSharePoller() throws {
        let repoURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let service = RepoBranchService(pollInterval: 60) { _ in "main" }
        service.subscribe(path: repoURL.path, id: UUID()) { _ in }
        service.subscribe(path: repoURL.appendingPathComponent(".").path, id: UUID()) { _ in }

        #expect(service.activePollerCount == 1)
    }

    @Test("inactive paths do not poll until activated")
    func inactivePathsPauseUntilActivated() async throws {
        let repoURL = try makeTempDirectory()
        let otherURL = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: otherURL)
        }

        let probe = ResolverProbe(fixed: "main")
        let service = RepoBranchService(pollInterval: 60) { path in probe.record(path) }
        service.setActiveRootPaths([otherURL.path])
        service.subscribe(path: repoURL.path, id: UUID()) { _ in }

        try? await Task.sleep(for: .milliseconds(80))
        #expect(service.activePollerCount == 0)
        #expect(probe.calls == 0)

        service.setActiveRootPaths([repoURL.path])
        await Self.waitUntil { probe.calls == 1 }
        #expect(service.activePollerCount == 1)
    }

    @Test("repo activity refreshes active branch subscriptions without polling")
    func repoActivityRefreshesActiveBranchSubscriptionsWithoutPolling() async throws {
        let repoURL = try makeTempDirectory()
        let childURL = repoURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let watcherProbe = TestRepoActivityWatcherProbe()
        let scheduler = TestRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        let probe = ResolverProbe(queue: ["main", "feature/activity"])
        let service = RepoBranchService(
            pollInterval: 60,
            resolver: { path in probe.record(path) },
            activityMonitor: monitor
        )
        service.setActiveRootPaths([repoURL.path])
        var delivered: [String?] = []

        service.subscribe(path: childURL.path, id: UUID()) { delivered.append($0) }
        await Self.waitUntil { delivered.last == "main" }

        #expect(service.activePollerCount == 0)
        #expect(service.activeActivitySubscriptionCount == 1)
        #expect(watcherProbe.createdPaths == [repoURL.path])
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        watcherProbe.trigger(
            rootPath: repoURL.path,
            events: [RepoActivityEvent(path: repoURL.appendingPathComponent(".git/HEAD").path, isDirectory: false)]
        )
        scheduler.runAll()

        await Self.waitUntil { delivered.last == "feature/activity" }
        #expect(probe.paths == [childURL.path, childURL.path])
    }

    @Test("branch activity subscriptions follow active root changes")
    func branchActivitySubscriptionsFollowActiveRootChanges() async throws {
        let repoURL = try makeTempDirectory()
        let childURL = repoURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let watcherProbe = TestRepoActivityWatcherProbe()
        let monitor = RepoActivityMonitor(watcherFactory: watcherProbe.makeWatcher)
        let service = RepoBranchService(
            pollInterval: 60,
            resolver: { _ in "main" },
            activityMonitor: monitor
        )

        service.setActiveRootPaths([repoURL.path])
        service.subscribe(path: childURL.path, id: UUID()) { _ in }
        await Self.waitUntil { watcherProbe.createdPaths == [repoURL.path] }

        service.setActiveRootPaths([childURL.path])

        await Self.waitUntil { watcherProbe.createdPaths == [repoURL.path, childURL.path] }
        #expect(watcherProbe.createdPaths == [repoURL.path, childURL.path])
        #expect(service.activePollerCount == 0)
        #expect(service.activeActivitySubscriptionCount == 1)
        #expect(monitor.activeRootCount == 1)
        #expect(watcherProbe.liveCount == 1)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
