import Foundation
import Testing

@testable import Muxy

@Suite("WorkspaceMountPlanner")
@MainActor
struct WorkspaceMountPlannerTests {
    @Test("mounts only active worktree for project")
    func mountsOnlyActiveWorktreeForProject() {
        let projectID = UUID()
        let activeWorktreeID = UUID()
        let inactiveWorktreeID = UUID()
        let otherProjectID = UUID()
        let activeKey = WorktreeKey(projectID: projectID, worktreeID: activeWorktreeID)
        let inactiveKey = WorktreeKey(projectID: projectID, worktreeID: inactiveWorktreeID)
        let otherKey = WorktreeKey(projectID: otherProjectID, worktreeID: UUID())
        let roots: [WorktreeKey: SplitNode] = [
            activeKey: .tabArea(TabArea(projectPath: "/tmp/active")),
            inactiveKey: .tabArea(TabArea(projectPath: "/tmp/inactive")),
            otherKey: .tabArea(TabArea(projectPath: "/tmp/other")),
        ]

        let mounted = WorkspaceMountPlanner.mountedWorktreeKeys(
            projectID: projectID,
            activeWorktreeIDs: [projectID: activeWorktreeID, otherProjectID: otherKey.worktreeID],
            workspaceRoots: roots
        )

        #expect(mounted == [activeKey])
    }

    @Test("does not mount missing active worktree root")
    func doesNotMountMissingActiveWorktreeRoot() {
        let projectID = UUID()
        let activeWorktreeID = UUID()

        let mounted = WorkspaceMountPlanner.mountedWorktreeKeys(
            projectID: projectID,
            activeWorktreeIDs: [projectID: activeWorktreeID],
            workspaceRoots: [:]
        )

        #expect(mounted.isEmpty)
    }

    @Test("mounts only active tab content")
    func mountsOnlyActiveTabContent() throws {
        let area = TabArea(projectPath: "/tmp/project")
        area.createTab()
        let activeID = try #require(area.activeTabID)

        let mounted = WorkspaceMountPlanner.mountedTabs(in: area)

        #expect(mounted.map(\.id) == [activeID])
    }
}
