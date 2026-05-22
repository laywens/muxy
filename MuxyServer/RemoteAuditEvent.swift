import Foundation
import MuxyShared

public struct RemoteAuditEvent: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case succeeded
        case denied
        case failed
    }

    public let timestamp: Date
    public let clientID: UUID
    public let deviceID: UUID
    public let method: MuxyMethod
    public let projectID: UUID?
    public let argsSummary: String
    public let outcome: Outcome
    public let errorMessage: String?
    public let nonce: String?
    public let serverTimestamp: Int64?

    public init(
        timestamp: Date = Date(),
        clientID: UUID,
        deviceID: UUID,
        method: MuxyMethod,
        projectID: UUID?,
        argsSummary: String,
        outcome: Outcome,
        errorMessage: String? = nil,
        nonce: String? = nil,
        serverTimestamp: Int64? = nil
    ) {
        self.timestamp = timestamp
        self.clientID = clientID
        self.deviceID = deviceID
        self.method = method
        self.projectID = projectID
        self.argsSummary = argsSummary
        self.outcome = outcome
        self.errorMessage = errorMessage
        self.nonce = nonce
        self.serverTimestamp = serverTimestamp
    }
}
