import Foundation

@MainActor
final class VCSWorktreeAutoRefresher {
    private let appState: AppState
    private let projectStore: ProjectStore
    private let worktreeStore: WorktreeStore
    private let repoActivityMonitor: RepoActivityMonitor?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var activitySubscriptions: [String: RepoActivitySubscription] = [:]
    private var activityProjectIDs: [String: UUID] = [:]
    private var inFlight: Set<UUID> = []
    private var pending: Set<UUID> = []

    init(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        repoActivityMonitor: RepoActivityMonitor? = nil
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        self.repoActivityMonitor = repoActivityMonitor
        if repoActivityMonitor == nil {
            observe(.vcsDidRefresh)
            observe(.vcsRepoDidChange)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var activeNotificationObserverCount: Int {
        observers.count
    }

    var activeActivitySubscriptionCount: Int {
        activitySubscriptions.count
    }

    func syncActiveSubscriptions() {
        guard let repoActivityMonitor else { return }
        let desiredRoots = activeActivityRoots()
        for root in Array(activitySubscriptions.keys) where desiredRoots[root] == nil {
            stopActivitySubscription(for: root)
        }
        for (root, projectID) in desiredRoots {
            if activityProjectIDs[root] == projectID,
               activitySubscriptions[root] != nil
            {
                continue
            }
            stopActivitySubscription(for: root)
            guard let subscription = repoActivityMonitor.subscribe(
                watchPath: root,
                repoPath: root,
                handler: { [weak self] activity in
                    self?.handleActivity(activity, projectID: projectID)
                }
            )
            else { continue }
            activitySubscriptions[root] = subscription
            activityProjectIDs[root] = projectID
        }
    }

    private func observe(_ name: Notification.Name) {
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let path = notification.userInfo?["repoPath"] as? String else { return }
            MainActor.assumeIsolated {
                self?.handleRefresh(repoPath: path)
            }
        }
        observers.append(token)
    }

    private func activeActivityRoots() -> [String: UUID] {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return [:] }
        var roots = [Self.canonicalPath(project.path): projectID]
        if let worktreeID = appState.activeWorktreeID[projectID],
           let worktree = worktreeStore.worktree(projectID: projectID, worktreeID: worktreeID)
        {
            roots[Self.canonicalPath(worktree.path)] = projectID
        }
        return roots
    }

    private func handleActivity(_ activity: RepoActivity, projectID: UUID) {
        guard activity.events.contains(where: { Self.isGitMetadataPath($0.path, rootPath: activity.watchPath) }) else {
            return
        }
        guard let project = projectStore.projects.first(where: { $0.id == projectID }) else { return }
        handleRefresh(project: project)
    }

    private func handleRefresh(repoPath: String) {
        guard let projectID = worktreeStore.projectID(forWorktreePath: repoPath) else { return }
        guard let project = projectStore.projects.first(where: { $0.id == projectID }) else { return }
        handleRefresh(project: project)
    }

    private func handleRefresh(project: Project) {
        let projectID = project.id
        guard !inFlight.contains(projectID) else {
            pending.insert(projectID)
            return
        }
        runRefresh(project: project)
    }

    private func runRefresh(project: Project) {
        inFlight.insert(project.id)
        Task { [appState, worktreeStore, projectStore] in
            await WorktreeRefreshHelper.refresh(
                project: project,
                appState: appState,
                worktreeStore: worktreeStore,
                isRefreshing: nil,
                presentErrors: false
            )
            inFlight.remove(project.id)
            guard pending.remove(project.id) != nil else { return }
            guard let updated = projectStore.projects.first(where: { $0.id == project.id }) else { return }
            runRefresh(project: updated)
        }
    }

    private func stopActivitySubscription(for root: String) {
        activitySubscriptions[root]?.cancel()
        activitySubscriptions.removeValue(forKey: root)
        activityProjectIDs.removeValue(forKey: root)
    }

    private static func isGitMetadataPath(_ path: String, rootPath: String) -> Bool {
        let root = canonicalPath(rootPath)
        let candidate = canonicalPath(path)
        guard candidate == root || candidate.hasPrefix(root + "/") else { return false }
        let relativeStart = candidate.index(candidate.startIndex, offsetBy: root.count)
        let relative = candidate[relativeStart...].drop { $0 == "/" }
        return relative == ".git" || relative.hasPrefix(".git/")
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
