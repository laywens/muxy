import Foundation
import MuxyShared
import Testing

@testable import Muxy

@Suite("ApprovedDevicesStore")
struct ApprovedDevicesStoreTests {
    @Test("legacy approved devices decode with default non-admin scopes")
    func legacyApprovedDeviceDefaultsScopes() throws {
        let legacy = LegacyApprovedDevice(
            id: UUID(),
            name: "iPhone",
            tokenHash: String(repeating: "a", count: 64),
            approvedAt: Date(timeIntervalSince1970: 0),
            lastSeenAt: nil
        )

        let data = try JSONEncoder().encode(legacy)
        let device = try JSONDecoder().decode(ApprovedDevice.self, from: data)

        #expect(device.scopes == RemoteCapability.defaultDeviceScopes)
        #expect(!device.scopes.contains(.admin))
    }

    @Test("user editable device capabilities exclude admin")
    func userEditableDeviceCapabilitiesExcludeAdmin() {
        #expect(RemoteCapability.userEditableDeviceCapabilities == RemoteCapability.defaultDeviceCapabilities)
        #expect(!RemoteCapability.userEditableDeviceCapabilities.contains(.admin))
    }

    @MainActor
    @Test("device scopes can be toggled and persisted without enabling admin")
    func deviceScopesCanBeToggledAndPersistedWithoutAdmin() throws {
        let harness = try ApprovedDeviceStoreHarness()
        let deviceID = UUID()
        let store = harness.makeStore()

        store.approve(deviceID: deviceID, name: "iPhone", token: "token")
        store.setScope(.terminalInput, enabled: false, for: deviceID)
        store.setScope(.admin, enabled: true, for: deviceID)

        var expected = RemoteCapability.defaultDeviceScopes
        expected.remove(.terminalInput)
        #expect(store.capabilities(for: deviceID) == expected)
        #expect(!store.capabilities(for: deviceID).contains(.admin))

        let reloaded = harness.makeStore()
        #expect(reloaded.capabilities(for: deviceID) == expected)
    }

    @MainActor
    @Test("re-approving an existing device preserves configured scopes")
    func reapprovingDevicePreservesConfiguredScopes() throws {
        let harness = try ApprovedDeviceStoreHarness()
        let deviceID = UUID()
        let store = harness.makeStore()

        store.approve(deviceID: deviceID, name: "iPhone", token: "first")
        store.setScope(.vcsDestructive, enabled: false, for: deviceID)
        store.approve(deviceID: deviceID, name: "iPhone", token: "second")

        #expect(!store.capabilities(for: deviceID).contains(.vcsDestructive))
        #expect(store.validate(deviceID: deviceID, token: "second") != nil)
    }

    private struct LegacyApprovedDevice: Encodable {
        let id: UUID
        let name: String
        let tokenHash: String
        let approvedAt: Date
        let lastSeenAt: Date?
    }

    private struct ApprovedDeviceStoreHarness {
        let fileURL: URL

        init() throws {
            fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ApprovedDevicesStoreTests-\(UUID().uuidString).json")
            try? FileManager.default.removeItem(at: fileURL)
        }

        @MainActor
        func makeStore() -> ApprovedDevicesStore {
            ApprovedDevicesStore(store: CodableFileStore<[ApprovedDevice]>(fileURL: fileURL))
        }
    }
}
