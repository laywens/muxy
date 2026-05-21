import Foundation
import Security

enum RemoteSessionTokensError: Error {
    case randomGenerationFailed(OSStatus)
}

final class RemoteSessionTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokensByClient: [UUID: String] = [:]

    func issue(for clientID: UUID) throws -> String {
        let token = try Self.randomHex(byteCount: 32)
        set(token, for: clientID)
        return token
    }

    func set(_ token: String, for clientID: UUID) {
        lock.lock()
        tokensByClient[clientID] = token
        lock.unlock()
    }

    func validate(clientID: UUID, providedToken: String?) -> Bool {
        guard let providedToken else { return false }
        lock.lock()
        let expected = tokensByClient[clientID]
        lock.unlock()
        guard let expected else { return false }
        return Self.constantTimeEquals(expected, providedToken)
    }

    func remove(clientID: UUID) {
        lock.lock()
        tokensByClient.removeValue(forKey: clientID)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        tokensByClient.removeAll()
        lock.unlock()
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }

    private static func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw RemoteSessionTokensError.randomGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
