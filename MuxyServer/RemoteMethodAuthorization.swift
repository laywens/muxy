import Foundation
import MuxyShared

enum RemoteMethodAuthorization {
    static func requiredCapability(for method: MuxyMethod) -> RemoteCapability? {
        switch method {
        case .pairDevice,
             .beginAuthentication,
             .authenticateDevice:
            nil

        case .listProjects,
             .selectProject,
             .listWorktrees,
             .selectWorktree,
             .getWorkspace,
             .createTab,
             .closeTab,
             .selectTab,
             .splitArea,
             .closeArea,
             .focusArea,
             .registerDevice,
             .getProjectLogo,
             .listNotifications,
             .markNotificationRead,
             .subscribe,
             .unsubscribe:
            .projectRead

        case .getTerminalContent:
            .terminalView

        case .terminalInput,
             .terminalResize,
             .terminalScroll,
             .takeOverPane,
             .releasePane:
            .terminalInput

        case .getVCSStatus,
             .vcsRefresh,
             .vcsListBranches,
             .vcsGetDiff:
            .vcsRead

        case .vcsStageFiles,
             .vcsUnstageFiles,
             .vcsSwitchBranch,
             .vcsCreateBranch,
             .vcsCreatePR,
             .vcsAddWorktree:
            .vcsWrite

        case .vcsCommit,
             .vcsPush,
             .vcsPull,
             .vcsDiscardFiles,
             .vcsMergePullRequest,
             .vcsRemoveWorktree:
            .vcsDestructive
        }
    }

    static func requiredCapability(for event: MuxyEventKind) -> RemoteCapability {
        switch event {
        case .workspaceChanged,
             .notificationReceived,
             .projectsChanged,
             .themeChanged:
            .projectRead

        case .terminalOutput,
             .terminalSnapshot,
             .paneOwnershipChanged:
            .terminalView
        }
    }

    static func requiresDestructiveConfirmation(_ method: MuxyMethod) -> Bool {
        requiredCapability(for: method) == .vcsDestructive
    }

    static func actionName(for method: MuxyMethod) -> String {
        switch method {
        case .vcsCommit:
            "commit"
        case .vcsPush:
            "push"
        case .vcsPull:
            "pull"
        case .vcsDiscardFiles:
            "discard files"
        case .vcsMergePullRequest:
            "merge pull request"
        case .vcsRemoveWorktree:
            "remove worktree"
        default:
            method.rawValue
        }
    }
}
