import Foundation

public enum RemoteCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case projectRead = "project.read"
    case terminalView = "terminal.view"
    case terminalInput = "terminal.input"
    case vcsRead = "vcs.read"
    case vcsWrite = "vcs.write"
    case vcsDestructive = "vcs.destructive"
    case admin

    public static let defaultDeviceCapabilities: [RemoteCapability] = [
        .projectRead,
        .terminalView,
        .terminalInput,
        .vcsRead,
        .vcsWrite,
        .vcsDestructive,
    ]

    public static let defaultDeviceScopes: Set<RemoteCapability> = Set(defaultDeviceCapabilities)

    public static let userEditableDeviceCapabilities: [RemoteCapability] = defaultDeviceCapabilities

    public var displayName: String {
        switch self {
        case .projectRead:
            "Projects"
        case .terminalView:
            "View terminals"
        case .terminalInput:
            "Control terminals"
        case .vcsRead:
            "View source control"
        case .vcsWrite:
            "Edit source control"
        case .vcsDestructive:
            "Destructive source control"
        case .admin:
            "Admin"
        }
    }

    public static func ordered(_ scopes: Set<RemoteCapability>) -> [RemoteCapability] {
        allCases.filter { scopes.contains($0) }
    }
}
