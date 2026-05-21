import Foundation
import Security
import Testing

@testable import Muxy

@Suite("RemoteServerIdentityStore")
struct RemoteServerIdentityStoreTests {
    @Test("creates reusable TLS identity and stable fingerprint")
    func createsReusableIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-identity-\(UUID().uuidString)", isDirectory: true)
        let store = RemoteServerIdentityStore(directory: directory)

        let first = try store.loadOrCreateIdentity(commonName: "Muxy Test")
        let second = try store.loadOrCreateIdentity(commonName: "Muxy Test")

        #expect(first.fingerprint == second.fingerprint)
        #expect(first.certificateDER == second.certificateDER)
        #expect(first.fingerprint.count == 64)
    }

    @Test("persists identity material in private files")
    func persistsPrivateIdentityMaterial() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-identity-\(UUID().uuidString)", isDirectory: true)
        let store = RemoteServerIdentityStore(directory: directory)

        _ = try store.loadOrCreateIdentity(commonName: "Muxy Test")

        let keyURL = directory.appendingPathComponent("remote-server-key.der")
        let certURL = directory.appendingPathComponent("remote-server-cert.der")
        let keyAttributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        let certAttributes = try FileManager.default.attributesOfItem(atPath: certURL.path)

        #expect((keyAttributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        #expect((certAttributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
    }
}
