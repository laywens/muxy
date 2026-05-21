import Foundation
import Security

public struct RemoteServerTLSIdentity: @unchecked Sendable {
    public let secIdentity: sec_identity_t
    public let certificateDER: Data
    public let fingerprint: String

    public init(secIdentity: sec_identity_t, certificateDER: Data, fingerprint: String) {
        self.secIdentity = secIdentity
        self.certificateDER = certificateDER
        self.fingerprint = fingerprint
    }
}
