import Foundation

struct RepoActivityEvent: Equatable {
    let path: String
    let isDirectory: Bool
}

struct RepoActivity: Equatable {
    let watchPath: String
    let repoPath: String?
    let events: [RepoActivityEvent]
}

@MainActor
protocol RepoActivityScheduling: AnyObject {
    func schedule(
        key: String,
        delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    )

    func cancel(key: String)
}

@MainActor
final class RepoActivityMonitor {
    typealias WatcherFactory = @MainActor (
        _ watchPath: String,
        _ handler: @escaping @MainActor @Sendable ([RepoActivityEvent]) -> Void
    ) -> (any FileSystemWatching)?

    @ObservationIgnored private let watcherFactory: WatcherFactory
    @ObservationIgnored private let scheduler: any RepoActivityScheduling
    @ObservationIgnored private let debounceDelay: Duration
    @ObservationIgnored private var roots: [String: RootState] = [:]

    var activeRootCount: Int {
        roots.count
    }

    var activeSubscriberCount: Int {
        roots.values.reduce(0) { $0 + $1.subscribers.count }
    }

    init(
        debounceDelay: Duration = .milliseconds(300),
        watcherFactory: @escaping WatcherFactory = RepoActivityMonitor.makeFileSystemWatcher,
        scheduler: any RepoActivityScheduling = RepoActivityTaskScheduler()
    ) {
        self.debounceDelay = debounceDelay
        self.watcherFactory = watcherFactory
        self.scheduler = scheduler
    }

    func subscribe(
        watchPath: String,
        repoPath: String? = nil,
        handler: @escaping @MainActor (RepoActivity) -> Void
    ) -> RepoActivitySubscription? {
        let rootKey = canonicalPath(watchPath)
        let id = UUID()
        if roots[rootKey] == nil {
            guard let watcher = watcherFactory(rootKey, { [weak self] events in
                self?.handle(events: events, rootKey: rootKey)
            })
            else { return nil }
            roots[rootKey] = RootState(watchPath: rootKey, watcher: watcher)
        }
        roots[rootKey]?.subscribers[id] = Subscriber(
            repoPath: repoPath.map(canonicalPath),
            handler: handler
        )
        return RepoActivitySubscription(id: id, rootKey: rootKey, monitor: self)
    }

    fileprivate func unsubscribe(id: UUID, rootKey: String) {
        guard var state = roots[rootKey] else { return }
        state.subscribers.removeValue(forKey: id)
        guard state.subscribers.isEmpty else {
            roots[rootKey] = state
            return
        }
        scheduler.cancel(key: rootKey)
        roots.removeValue(forKey: rootKey)
    }

    private func handle(events: [RepoActivityEvent], rootKey: String) {
        guard var state = roots[rootKey] else { return }
        let included = events.filter { event in
            !RepoActivityIgnoreRules.shouldIgnore(
                path: event.path,
                rootPath: state.watchPath,
                isDirectory: event.isDirectory
            )
        }
        guard !included.isEmpty else { return }
        state.pendingEvents.append(contentsOf: included)
        roots[rootKey] = state
        scheduler.cancel(key: rootKey)
        scheduler.schedule(key: rootKey, delay: debounceDelay) { [weak self] in
            self?.flush(rootKey: rootKey)
        }
    }

    private func flush(rootKey: String) {
        guard var state = roots[rootKey], !state.pendingEvents.isEmpty else { return }
        let events = state.pendingEvents
        state.pendingEvents.removeAll()
        roots[rootKey] = state
        scheduler.cancel(key: rootKey)
        for subscriber in state.subscribers.values {
            let activity = RepoActivity(
                watchPath: state.watchPath,
                repoPath: subscriber.repoPath,
                events: events
            )
            subscriber(activity)
        }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func makeFileSystemWatcher(
        rootPath: String,
        handler: @escaping @MainActor @Sendable ([RepoActivityEvent]) -> Void
    ) -> (any FileSystemWatching)? {
        FileSystemWatcher(directoryPath: rootPath) { events in
            let activityEvents = events.map {
                RepoActivityEvent(path: $0.path, isDirectory: $0.isDirectory)
            }
            Task { @MainActor in
                handler(activityEvents)
            }
        }
    }

    private struct RootState {
        let watchPath: String
        let watcher: any FileSystemWatching
        var subscribers: [UUID: Subscriber] = [:]
        var pendingEvents: [RepoActivityEvent] = []
    }

    private struct Subscriber {
        let repoPath: String?
        let handler: @MainActor (RepoActivity) -> Void

        @MainActor
        func callAsFunction(_ activity: RepoActivity) {
            handler(activity)
        }
    }
}

final class RepoActivitySubscription: @unchecked Sendable {
    private let id: UUID
    private let rootKey: String
    private weak var monitor: RepoActivityMonitor?
    private let lock = NSLock()
    private var cancelled = false

    fileprivate init(id: UUID, rootKey: String, monitor: RepoActivityMonitor) {
        self.id = id
        self.rootKey = rootKey
        self.monitor = monitor
    }

    deinit {
        guard markCancelled() else { return }
        let monitor = monitor
        Task { @MainActor [id, rootKey, weak monitor] in
            monitor?.unsubscribe(id: id, rootKey: rootKey)
        }
    }

    @MainActor
    func cancel() {
        guard markCancelled() else { return }
        monitor?.unsubscribe(id: id, rootKey: rootKey)
    }

    private func markCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        cancelled = true
        return true
    }
}

@MainActor
private final class RepoActivityTaskScheduler: RepoActivityScheduling {
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func schedule(
        key: String,
        delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        cancel(key: key)
        tasks[key] = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                action()
            }
        }
    }

    func cancel(key: String) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }
}
