import Foundation

@MainActor
enum WorkspaceMountPlanner {
    static func mountedWorktreeKeys(
        projectID: UUID,
        activeWorktreeIDs: [UUID: UUID],
        workspaceRoots: [WorktreeKey: SplitNode]
    ) -> [WorktreeKey] {
        guard let worktreeID = activeWorktreeIDs[projectID] else { return [] }
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        guard workspaceRoots[key] != nil else { return [] }
        return [key]
    }

    static func mountedTabs(in area: TabArea) -> [TerminalTab] {
        guard let activeTab = area.activeTab else { return [] }
        return [activeTab]
    }
}
