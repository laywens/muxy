import CryptoKit
import Foundation
import MuxyShared
import os

private let logger = Logger(subsystem: "app.muxy", category: "ApprovedDevicesStore")

struct ApprovedDevice: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let tokenHash: String
    let approvedAt: Date
    var lastSeenAt: Date?
    var scopes: Set<RemoteCapability>

    init(
        id: UUID,
        name: String,
        tokenHash: String,
        approvedAt: Date,
        lastSeenAt: Date?,
        scopes: Set<RemoteCapability> = RemoteCapability.defaultDeviceScopes
    ) {
        self.id = id
        self.name = name
        self.tokenHash = tokenHash
        self.approvedAt = approvedAt
        self.lastSeenAt = lastSeenAt
        self.scopes = scopes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case tokenHash
        case approvedAt
        case lastSeenAt
        case scopes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tokenHash = try container.decode(String.self, forKey: .tokenHash)
        approvedAt = try container.decode(Date.self, forKey: .approvedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        scopes = try container.decodeIfPresent(Set<RemoteCapability>.self, forKey: .scopes)
            ?? RemoteCapability.defaultDeviceScopes
    }
}

@MainActor
@Observable
final class ApprovedDevicesStore {
    static let shared = ApprovedDevicesStore(store: defaultStore)

    private static let defaultStore = CodableFileStore<[ApprovedDevice]>(
        fileURL: MuxyFileStorage.fileURL(filename: "approved-devices.json"),
        options: CodableFileStoreOptions(filePermissions: FilePermissions.privateFile)
    )

    private let store: CodableFileStore<[ApprovedDevice]>
    private(set) var devices: [ApprovedDevice] = []

    var onRevoke: ((UUID) -> Void)?

    init(store: CodableFileStore<[ApprovedDevice]>) {
        self.store = store
        do {
            devices = try store.load() ?? []
        } catch {
            logger.error("Failed to load approved devices: \(error)")
        }
    }

    func approve(deviceID: UUID, name: String, token: String) {
        let hash = Self.hash(token)
        let now = Date()
        if let index = devices.firstIndex(where: { $0.id == deviceID }) {
            devices[index] = ApprovedDevice(
                id: deviceID,
                name: name,
                tokenHash: hash,
                approvedAt: devices[index].approvedAt,
                lastSeenAt: now,
                scopes: devices[index].scopes
            )
        } else {
            devices.append(ApprovedDevice(
                id: deviceID,
                name: name,
                tokenHash: hash,
                approvedAt: now,
                lastSeenAt: now
            ))
        }
        save()
    }

    func validate(deviceID: UUID, token: String) -> ApprovedDevice? {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return nil }
        let provided = Self.hash(token)
        guard Self.constantTimeEquals(device.tokenHash, provided) else { return nil }
        return device
    }

    func touch(deviceID: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].lastSeenAt = Date()
        save()
    }

    func rename(deviceID: UUID, to newName: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].name = newName
        save()
    }

    func capabilities(for deviceID: UUID) -> Set<RemoteCapability> {
        devices.first(where: { $0.id == deviceID })?.scopes ?? RemoteCapability.defaultDeviceScopes
    }

    func setScope(_ scope: RemoteCapability, enabled: Bool, for deviceID: UUID) {
        guard scope != .admin,
              let index = devices.firstIndex(where: { $0.id == deviceID })
        else { return }
        if enabled {
            devices[index].scopes.insert(scope)
        } else {
            devices[index].scopes.remove(scope)
        }
        save()
    }

    func revoke(deviceID: UUID) {
        devices.removeAll { $0.id == deviceID }
        save()
        onRevoke?(deviceID)
    }

    func replaceDevices(_ newDevices: [ApprovedDevice]) {
        devices = newDevices
        save()
    }

    nonisolated static func hash(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func challengeResponse(
        tokenHash: String,
        nonce: String,
        serverTimestamp: Int64,
        deviceFingerprint: String
    ) -> String {
        guard let keyData = hexData(tokenHash) else { return "" }
        let key = SymmetricKey(data: keyData)
        let message = "\(nonce)\n\(serverTimestamp)\n\(deviceFingerprint)"
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func constantTimeHexEquals(_ lhs: String, _ rhs: String) -> Bool {
        constantTimeEquals(lhs, rhs)
    }

    nonisolated private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }

    nonisolated private static func hexData(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private func save() {
        do {
            try store.save(devices)
            SettingsJSONStore.syncUserSettingsFileWithCurrentSettings()
        } catch {
            logger.error("Failed to save approved devices: \(error)")
        }
    }
}
