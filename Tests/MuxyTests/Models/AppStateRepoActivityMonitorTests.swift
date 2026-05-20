import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("AppState repo activity monitor")
struct AppStateRepoActivityMonitorTests {
    @Test("keeps injected repo activity monitor")
    func keepsInjectedRepoActivityMonitor() {
        let monitor = RepoActivityMonitor()
        let appState = AppState(
            selectionStore: SelectionStoreStub(),
            terminalViews: TerminalViewRemovingStub(),
            workspacePersistence: WorkspacePersistenceStub(),
            repoActivityMonitor: monitor
        )

        #expect(appState.repoActivityMonitor === monitor)
    }

    @Test("configures shared VCS state store with injected repo activity monitor")
    func configuresSharedVCSStateStoreWithInjectedRepoActivityMonitor() throws {
        let root = try makeTempDirectory()
        defer {
            VCSStateStore.shared.remove(path: root.path)
            VCSStateStore.shared.configure(activityMonitor: RepoActivityMonitor())
            try? FileManager.default.removeItem(at: root)
        }
        let watcherProbe = TestRepoActivityWatcherProbe()
        let monitor = RepoActivityMonitor(watcherFactory: watcherProbe.makeWatcher)
        _ = AppState(
            selectionStore: SelectionStoreStub(),
            terminalViews: TerminalViewRemovingStub(),
            workspacePersistence: WorkspacePersistenceStub(),
            repoActivityMonitor: monitor
        )

        let state = VCSStateStore.shared.state(for: root.path)
        state.activate(reason: .visibleTab)

        #expect(watcherProbe.createdPaths == [root.path])
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        state.deactivate(reason: .visibleTab)
    }

    @Test("configures injected branch service with repo activity monitor")
    func configuresInjectedBranchServiceWithRepoActivityMonitor() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = TestRepoActivityWatcherProbe()
        let monitor = RepoActivityMonitor(watcherFactory: watcherProbe.makeWatcher)
        let branchService = RepoBranchService(pollInterval: 60) { _ in "main" }
        _ = AppState(
            selectionStore: SelectionStoreStub(),
            terminalViews: TerminalViewRemovingStub(),
            workspacePersistence: WorkspacePersistenceStub(),
            repoBranchService: branchService,
            repoActivityMonitor: monitor
        )
        var delivered: [String?] = []

        branchService.setActiveRootPaths([root.path])
        branchService.subscribe(path: root.path, id: UUID()) { delivered.append($0) }
        try await waitUntil { delivered.last == "main" }

        #expect(branchService.activePollerCount == 0)
        #expect(branchService.activeActivitySubscriptionCount == 1)
        #expect(watcherProbe.createdPaths == [root.path])
        #expect(monitor.activeRootCount == 1)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-appstate-activity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class WorkspacePersistenceStub: WorkspacePersisting {
    private var snapshots: [WorkspaceSnapshot] = []

    func loadWorkspaces() throws -> [WorkspaceSnapshot] {
        snapshots
    }

    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {
        snapshots = workspaces
    }
}

@MainActor
private final class SelectionStoreStub: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID] = [:]

    func loadActiveProjectID() -> UUID? {
        activeProjectID
    }

    func saveActiveProjectID(_ id: UUID?) {
        activeProjectID = id
    }

    func loadActiveWorktreeIDs() -> [UUID: UUID] {
        activeWorktreeIDs
    }

    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {
        activeWorktreeIDs = ids
    }
}

@MainActor
private final class TerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}
