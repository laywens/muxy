import Foundation

@testable import Muxy

final class TestRepoActivityWatcherProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var watchersByRoot: [String: WeakTestRepoActivityWatcher] = [:]
    private var storedCreatedPaths: [String] = []
    private var liveWatcherCount = 0

    var createdPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedCreatedPaths
    }

    var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return liveWatcherCount
    }

    @MainActor
    func makeWatcher(
        rootPath: String,
        handler: @escaping @MainActor @Sendable ([RepoActivityEvent]) -> Void
    ) -> (any FileSystemWatching)? {
        let canonical = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        lock.lock()
        storedCreatedPaths.append(canonical)
        liveWatcherCount += 1
        lock.unlock()
        let watcher = TestRepoActivityWatcher(handler: handler) { [weak self] in
            self?.recordWatcherDeinit()
        }
        watchersByRoot[canonical] = WeakTestRepoActivityWatcher(watcher)
        return watcher
    }

    @MainActor
    func trigger(rootPath: String, events: [RepoActivityEvent]) {
        let canonical = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        watchersByRoot[canonical]?.value?.trigger(events)
    }

    private func recordWatcherDeinit() {
        lock.lock()
        liveWatcherCount -= 1
        lock.unlock()
    }
}

private final class WeakTestRepoActivityWatcher {
    weak var value: TestRepoActivityWatcher?

    init(_ value: TestRepoActivityWatcher) {
        self.value = value
    }
}

private final class TestRepoActivityWatcher: FileSystemWatching {
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
