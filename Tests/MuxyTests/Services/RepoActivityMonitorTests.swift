import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("RepoActivityMonitor")
struct RepoActivityMonitorTests {
    @Test("canonical paths share one watcher")
    func canonicalPathsShareOneWatcher() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )

        let first = monitor.subscribe(watchPath: root.path) { _ in }
        let second = monitor.subscribe(watchPath: root.appendingPathComponent(".").path) { _ in }

        #expect(first != nil)
        #expect(second != nil)
        #expect(watcherProbe.createdCount == 1)
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)
    }

    @Test("active subscriber count tracks shared root fan-out")
    func activeSubscriberCountTracksSharedRootFanOut() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )

        let first = try #require(monitor.subscribe(watchPath: root.path) { _ in })
        let second = try #require(monitor.subscribe(watchPath: root.appendingPathComponent(".").path) { _ in })

        #expect(monitor.activeRootCount == 1)
        #expect(monitor.activeSubscriberCount == 2)

        first.cancel()
        #expect(monitor.activeRootCount == 1)
        #expect(monitor.activeSubscriberCount == 1)

        second.cancel()
        #expect(monitor.activeRootCount == 0)
        #expect(monitor.activeSubscriberCount == 0)
    }

    @Test("fans out debounced activity to every subscriber")
    func fansOutDebouncedActivityToEverySubscriber() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var first: [RepoActivity] = []
        var second: [RepoActivity] = []
        let firstSubscription = monitor.subscribe(watchPath: root.path) { activity in first.append(activity) }
        let secondSubscription = monitor.subscribe(watchPath: root.path) { activity in second.append(activity) }

        watcherProbe.trigger(
            rootPath: root.path,
            events: [RepoActivityEvent(path: root.appendingPathComponent("Package.swift").path, isDirectory: false)]
        )
        scheduler.runAll()

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first.first?.events.map(\.path) == [root.appendingPathComponent("Package.swift").path])
        #expect(second.first == first.first)
        #expect(firstSubscription != nil)
        #expect(secondSubscription != nil)
    }

    @Test("delivers subscriber repo path separately from watch path")
    func deliversSubscriberRepoPathSeparatelyFromWatchPath() throws {
        let repo = try makeTempDirectory()
        let watched = repo.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var delivered: [RepoActivity] = []
        let subscription = monitor.subscribe(watchPath: watched.path, repoPath: repo.path) { delivered.append($0) }

        watcherProbe.trigger(
            rootPath: watched.path,
            events: [RepoActivityEvent(path: watched.appendingPathComponent("Sources/App.swift").path, isDirectory: false)]
        )
        scheduler.runAll()

        #expect(delivered.count == 1)
        #expect(delivered.first?.watchPath == watched.path)
        #expect(delivered.first?.repoPath == repo.path)
        #expect(subscription != nil)
    }

    @Test("drops ignored activity before scheduling debounce")
    func dropsIgnoredActivityBeforeSchedulingDebounce() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var delivered: [RepoActivity] = []
        let subscription = monitor.subscribe(watchPath: root.path) { delivered.append($0) }

        watcherProbe.trigger(
            rootPath: root.path,
            events: [RepoActivityEvent(path: root.appendingPathComponent("node_modules/pkg/index.js").path, isDirectory: false)]
        )
        scheduler.runAll()

        #expect(scheduler.scheduleCount == 0)
        #expect(delivered.isEmpty)
        #expect(subscription != nil)
    }

    @Test("coalesces multiple events into one delivery")
    func coalescesMultipleEventsIntoOneDelivery() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var delivered: [RepoActivity] = []
        let subscription = monitor.subscribe(watchPath: root.path) { delivered.append($0) }

        watcherProbe.trigger(
            rootPath: root.path,
            events: [RepoActivityEvent(path: root.appendingPathComponent("Package.swift").path, isDirectory: false)]
        )
        watcherProbe.trigger(
            rootPath: root.path,
            events: [RepoActivityEvent(path: root.appendingPathComponent("Muxy/App.swift").path, isDirectory: false)]
        )
        scheduler.runAll()

        #expect(scheduler.scheduleCount == 2)
        #expect(scheduler.cancelCount == 1)
        #expect(delivered.count == 1)
        #expect(delivered.first?.events.map(\.path) == [
            root.appendingPathComponent("Package.swift").path,
            root.appendingPathComponent("Muxy/App.swift").path
        ])
        #expect(subscription != nil)
    }

    @Test("tears down watcher after last subscription cancels")
    func tearsDownWatcherAfterLastSubscriptionCancels() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        let first = try #require(monitor.subscribe(watchPath: root.path) { _ in })
        let second = try #require(monitor.subscribe(watchPath: root.path) { _ in })

        first.cancel()
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        second.cancel()
        #expect(watcherProbe.liveCount == 0)
        #expect(monitor.activeRootCount == 0)
    }

    @Test("tears down watcher when subscription token is released")
    func tearsDownWatcherWhenSubscriptionTokenIsReleased() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var subscription = monitor.subscribe(watchPath: root.path) { _ in }

        #expect(subscription != nil)
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        subscription = nil

        try await waitForTeardown(monitor: monitor, watcherProbe: watcherProbe)

        #expect(watcherProbe.liveCount == 0)
        #expect(monitor.activeRootCount == 0)
    }

    @Test("cleans up scheduled debounce after delivery")
    func cleansUpScheduledDebounceAfterDelivery() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = RepoActivityWatcherProbe()
        let scheduler = ManualRepoActivityScheduler()
        let monitor = RepoActivityMonitor(
            watcherFactory: watcherProbe.makeWatcher,
            scheduler: scheduler
        )
        var delivered: [RepoActivity] = []
        let subscription = monitor.subscribe(watchPath: root.path) { delivered.append($0) }
        let rootKey = URL(fileURLWithPath: root.path).standardizedFileURL.path

        watcherProbe.trigger(
            rootPath: root.path,
            events: [RepoActivityEvent(path: root.appendingPathComponent("Package.swift").path, isDirectory: false)]
        )

        #expect(scheduler.hasScheduledAction(key: rootKey))

        scheduler.runAll(retainingScheduledActions: true)

        #expect(delivered.count == 1)
        #expect(!scheduler.hasScheduledAction(key: rootKey))
        #expect(subscription != nil)
    }
}

private final class RepoActivityWatcherProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var watchersByRoot: [String: WeakFakeRepoActivityWatcher] = [:]

    var createdCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _createdCount
    }

    var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _liveCount
    }

    private var _createdCount = 0
    private var _liveCount = 0

    @MainActor
    func makeWatcher(
        rootPath: String,
        handler: @escaping @MainActor @Sendable ([RepoActivityEvent]) -> Void
    ) -> (any FileSystemWatching)? {
        let canonical = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        lock.lock()
        _createdCount += 1
        _liveCount += 1
        lock.unlock()
        let watcher = FakeRepoActivityWatcher(handler: handler) { [weak self] in
            self?.recordWatcherDeinit()
        }
        watchersByRoot[canonical] = WeakFakeRepoActivityWatcher(watcher)
        return watcher
    }

    @MainActor
    func trigger(rootPath: String, events: [RepoActivityEvent]) {
        let canonical = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        watchersByRoot[canonical]?.value?.trigger(events)
    }

    private func recordWatcherDeinit() {
        lock.lock()
        _liveCount -= 1
        lock.unlock()
    }
}

private final class WeakFakeRepoActivityWatcher {
    weak var value: FakeRepoActivityWatcher?

    init(_ value: FakeRepoActivityWatcher) {
        self.value = value
    }
}

private final class FakeRepoActivityWatcher: FileSystemWatching {
    private let handler: @MainActor @Sendable ([RepoActivityEvent]) -> Void
    private let onDeinit: @Sendable () -> Void

    init(
        handler: @escaping @MainActor @Sendable ([RepoActivityEvent]) -> Void,
        onDeinit: @escaping @Sendable () -> Void
    ) {
        self.handler = handler
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }

    @MainActor
    func trigger(_ events: [RepoActivityEvent]) {
        handler(events)
    }
}

@MainActor
private final class ManualRepoActivityScheduler: RepoActivityScheduling {
    private var actions: [String: @MainActor @Sendable () -> Void] = [:]
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    func schedule(
        key: String,
        delay _: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        scheduleCount += 1
        actions[key] = action
    }

    func cancel(key: String) {
        guard actions.removeValue(forKey: key) != nil else { return }
        cancelCount += 1
    }

    func hasScheduledAction(key: String) -> Bool {
        actions[key] != nil
    }

    func runAll(retainingScheduledActions: Bool = false) {
        let pending = actions
        if !retainingScheduledActions {
            actions.removeAll()
        }
        for action in pending.values {
            action()
        }
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("muxy-repo-activity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func waitForTeardown(monitor: RepoActivityMonitor, watcherProbe: RepoActivityWatcherProbe) async throws {
    for _ in 0..<20 {
        if watcherProbe.liveCount == 0, monitor.activeRootCount == 0 {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
