import Foundation
import MuxyShared

public struct RemoteDestructiveActionRequest: Sendable, Equatable {
    public let clientID: UUID
    public let deviceID: UUID
    public let method: MuxyMethod
    public let actionName: String

    public init(clientID: UUID, deviceID: UUID, method: MuxyMethod, actionName: String) {
        self.clientID = clientID
        self.deviceID = deviceID
        self.method = method
        self.actionName = actionName
    }
}
