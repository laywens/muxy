import Crypto
import Foundation
import MuxyServer
import Security
import X509

enum RemoteServerIdentityStoreError: LocalizedError {
    case keyGenerationFailed
    case certificateCreationFailed
    case identityCreationFailed

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            "Could not generate the remote server TLS private key."
        case .certificateCreationFailed:
            "Could not create the remote server TLS certificate."
        case .identityCreationFailed:
            "Could not create the remote server TLS identity."
        }
    }
}

struct RemoteServerIdentityStore {
    private let directory: URL

    init(directory: URL = MuxyFileStorage.appSupportDirectory().appendingPathComponent("remote-server", isDirectory: true)) {
        self.directory = directory
    }

    func loadOrCreateIdentity(commonName: String) throws -> RemoteServerTLSIdentity {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: FilePermissions.privateDirectory]
        )

        if let stored = try loadStoredIdentity() {
            return stored
        }

        let privateKey = try makePrivateKey()
        let certificateDER = try makeCertificateDER(privateKey: privateKey, commonName: commonName)
        try write(certificateDER, to: certificateURL)

        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let identityRef = SecIdentityCreate(nil, certificate, privateKey),
              let identity = sec_identity_create(identityRef)
        else {
            throw RemoteServerIdentityStoreError.identityCreationFailed
        }

        return RemoteServerTLSIdentity(
            secIdentity: identity,
            certificateDER: certificateDER,
            fingerprint: Self.fingerprint(for: certificateDER)
        )
    }

    private var keyURL: URL {
        directory.appendingPathComponent("remote-server-key.der")
    }

    private var certificateURL: URL {
        directory.appendingPathComponent("remote-server-cert.der")
    }

    private func loadStoredIdentity() throws -> RemoteServerTLSIdentity? {
        guard FileManager.default.fileExists(atPath: keyURL.path),
              FileManager.default.fileExists(atPath: certificateURL.path)
        else { return nil }

        let keyData = try Data(contentsOf: keyURL)
        let certificateDER = try Data(contentsOf: certificateURL)
        guard let privateKey = SecKeyCreateWithData(
            keyData as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            ] as CFDictionary,
            nil
        ),
            let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
            let identityRef = SecIdentityCreate(nil, certificate, privateKey),
            let identity = sec_identity_create(identityRef)
        else {
            return nil
        }

        return RemoteServerTLSIdentity(
            secIdentity: identity,
            certificateDER: certificateDER,
            fingerprint: Self.fingerprint(for: certificateDER)
        )
    }

    private func makePrivateKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(
            [
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits: 256,
            ] as CFDictionary,
            &error
        )
        else {
            throw error?.takeRetainedValue() ?? RemoteServerIdentityStoreError.keyGenerationFailed
        }
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw error?.takeRetainedValue() ?? RemoteServerIdentityStoreError.keyGenerationFailed
        }
        try write(keyData, to: keyURL)
        return key
    }

    private func makeCertificateDER(privateKey: SecKey, commonName: String) throws -> Data {
        let certificatePrivateKey = try Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName {
            CommonName(commonName)
        }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: certificatePrivateKey.publicKey,
            notValidBefore: now - 60,
            notValidAfter: now + TimeInterval(365 * 24 * 60 * 60),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
            },
            issuerPrivateKey: certificatePrivateKey
        )
        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        let der = SecCertificateCopyData(secCertificate) as Data
        guard !der.isEmpty else {
            throw RemoteServerIdentityStoreError.certificateCreationFailed
        }
        return der
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: FilePermissions.privateFile],
            ofItemAtPath: url.path
        )
    }

    private static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
