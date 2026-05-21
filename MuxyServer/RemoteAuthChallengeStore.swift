import Foundation
import Security

struct RemoteAuthChallenge {
    let challengeID: String
    let nonce: String
    let serverTimestamp: Int64
    let deviceID: UUID
    let deviceName: String
    let deviceFingerprint: String
    let issuedAt: Date
}

enum RemoteAuthChallengeStoreError: Error {
    case randomGenerationFailed(OSStatus)
}

final class RemoteAuthChallengeStore {
    private let challengeTTL: TimeInterval
    private let consumedNonceTTL: TimeInterval
    private var challenges: [String: RemoteAuthChallenge] = [:]
    private var consumedNonces: [String: Date] = [:]

    init(challengeTTL: TimeInterval = 30, consumedNonceTTL: TimeInterval = 300) {
        self.challengeTTL = challengeTTL
        self.consumedNonceTTL = consumedNonceTTL
    }

    func issue(
        deviceID: UUID,
        deviceName: String,
        deviceFingerprint: String,
        now: Date = Date()
    ) throws -> RemoteAuthChallenge {
        purgeExpired(now: now)
        let challengeID = try Self.randomHex(byteCount: 32)
        let challenge = try RemoteAuthChallenge(
            challengeID: challengeID,
            nonce: Self.randomHex(byteCount: 16),
            serverTimestamp: Int64((now.timeIntervalSince1970 * 1000).rounded()),
            deviceID: deviceID,
            deviceName: deviceName,
            deviceFingerprint: deviceFingerprint,
            issuedAt: now
        )
        challenges[challengeID] = challenge
        return challenge
    }

    func consume(challengeID: String, now: Date = Date()) -> RemoteAuthChallenge? {
        purgeExpired(now: now)
        guard let challenge = challenges.removeValue(forKey: challengeID) else { return nil }
        guard now.timeIntervalSince(challenge.issuedAt) <= challengeTTL else { return nil }
        guard consumedNonces[challenge.nonce] == nil else { return nil }
        consumedNonces[challenge.nonce] = now
        return challenge
    }

    private func purgeExpired(now: Date) {
        challenges = challenges.filter { _, challenge in
            now.timeIntervalSince(challenge.issuedAt) <= challengeTTL
        }
        consumedNonces = consumedNonces.filter { _, consumedAt in
            now.timeIntervalSince(consumedAt) <= consumedNonceTTL
        }
    }

    private static func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw RemoteAuthChallengeStoreError.randomGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
