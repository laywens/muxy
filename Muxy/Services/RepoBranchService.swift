import Foundation

@MainActor
@Observable
final class RepoBranchService {
    typealias BranchResolver = @Sendable (String) async -> String?
    typealias Listener = @MainActor (String?) -> Void

    static let shared = RepoBranchService()

    private struct Subscription {
        let id: UUID
        let listener: Listener
    }

    private(set) var branches: [String: String] = [:]
    private var listeners: [String: [Subscription]] = [:]
    private var pollers: [String: Task<Void, Never>] = [:]
    private var resolvePaths: [String: String] = [:]
    private var activeRootKeys: Set<String>?
    private let resolver: BranchResolver
    private let pollInterval: TimeInterval

    init(
        pollInterval: TimeInterval = 5,
        resolver: @escaping BranchResolver = RepoBranchService.defaultResolver
    ) {
        self.pollInterval = pollInterval
        self.resolver = resolver
    }

    @discardableResult
    func subscribe(path: String, id: UUID = UUID(), listener: @escaping Listener) -> UUID {
        let key = Self.canonicalKey(for: path)
        var current = listeners[key] ?? []
        let isFirst = current.isEmpty
        current.append(Subscription(id: id, listener: listener))
        listeners[key] = current
        resolvePaths[key] = path
        if isFirst, isActive(key: key) {
            startPoller(for: key)
        } else {
            listener(branches[key])
        }
        return id
    }

    func unsubscribe(path: String, id: UUID) {
        let key = Self.canonicalKey(for: path)
        guard var current = listeners[key] else { return }
        current.removeAll { $0.id == id }
        if current.isEmpty {
            listeners.removeValue(forKey: key)
            resolvePaths.removeValue(forKey: key)
            stopPoller(for: key)
        } else {
            listeners[key] = current
        }
    }

    func refresh(path: String) {
        let key = Self.canonicalKey(for: path)
        guard isActive(key: key) else { return }
        Task { @MainActor [weak self] in
            await self?.doRefresh(key)
        }
    }

    func currentBranch(for path: String) -> String? {
        branches[Self.canonicalKey(for: path)]
    }

    var activePollerCount: Int {
        pollers.count
    }

    var branchObserverCount: Int {
        listeners.values.reduce(0) { $0 + $1.count }
    }

    func setActiveRootPaths(_ paths: [String]) {
        activeRootKeys = Set(paths.map { Self.canonicalKey(for: $0) })
        reconcilePollers()
    }

    static let defaultResolver: BranchResolver = { path in
        let service = GitRepositoryService()
        guard let result = try? await service.currentBranch(repoPath: path) else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "HEAD" else { return nil }
        return trimmed
    }

    private func startPoller(for path: String) {
        guard pollers[path] == nil else { return }
        let interval = pollInterval
        pollers[path] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.doRefresh(path)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopPoller(for path: String) {
        pollers[path]?.cancel()
        pollers.removeValue(forKey: path)
        branches.removeValue(forKey: path)
    }

    private func doRefresh(_ path: String) async {
        guard isActive(key: path) else { return }
        let resolved = await resolver(resolvePaths[path] ?? path)
        guard !Task.isCancelled else { return }
        guard listeners[path] != nil else { return }
        if let resolved {
            branches[path] = resolved
        } else {
            branches.removeValue(forKey: path)
        }
        for sub in listeners[path] ?? [] {
            sub.listener(resolved)
        }
    }

    private func reconcilePollers() {
        for key in listeners.keys {
            if isActive(key: key) {
                startPoller(for: key)
            } else {
                stopPoller(for: key)
            }
        }
    }

    private func isActive(key: String) -> Bool {
        guard let activeRootKeys else { return true }
        return activeRootKeys.contains { root in
            key == root || key.hasPrefix(root + "/")
        }
    }

    private static func canonicalKey(for path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
    }
}
