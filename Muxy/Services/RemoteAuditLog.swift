import Foundation
import MuxyShared

struct RemoteAuditRecord: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable, Equatable {
        case succeeded
        case denied
        case failed
    }

    let id: UUID
    let timestamp: Date
    let clientID: UUID
    let deviceID: UUID
    let deviceName: String?
    let method: MuxyMethod
    let projectID: UUID?
    let argsSummary: String
    let outcome: Outcome
    let errorMessage: String?
    let nonce: String?
    let serverTimestamp: Int64?
}

struct RemoteAuditLog {
    static let shared = RemoteAuditLog(
        fileURL: MuxyFileStorage.appSupportDirectory()
            .appendingPathComponent("audit", isDirectory: true)
            .appendingPathComponent("remote.log")
    )

    static let defaultMaxBytes = 10 * 1024 * 1024
    static let defaultMaxRotatedFiles = 5

    let fileURL: URL
    let maxBytes: Int
    let maxRotatedFiles: Int

    init(
        fileURL: URL,
        maxBytes: Int = Self.defaultMaxBytes,
        maxRotatedFiles: Int = Self.defaultMaxRotatedFiles
    ) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.maxRotatedFiles = maxRotatedFiles
    }

    func append(_ record: RemoteAuditRecord) throws {
        try ensureDirectory()
        var line = try Self.encoder.encode(record)
        line.append(0x0A)
        try rotateIfNeeded(forAdditionalBytes: line.count)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
        try setPrivateFilePermissions(fileURL)
    }

    func recent(limit: Int = 100) throws -> [RemoteAuditRecord] {
        guard limit > 0 else { return [] }
        let records = try logURLs().reduce(into: [RemoteAuditRecord]()) { partial, url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else {
                throw RemoteAuditLogError.invalidUTF8(url)
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                try partial.append(Self.decoder.decode(RemoteAuditRecord.self, from: lineData))
            }
        }
        return Array(records.sorted(by: Self.newestFirst).prefix(limit))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func newestFirst(_ lhs: RemoteAuditRecord, _ rhs: RemoteAuditRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: FilePermissions.privateDirectory]
        )
    }

    private func rotateIfNeeded(forAdditionalBytes additionalBytes: Int) throws {
        guard maxBytes > 0,
              let currentBytes = try fileSize(fileURL),
              currentBytes + additionalBytes > maxBytes
        else { return }
        try rotate()
    }

    private func rotate() throws {
        let fileManager = FileManager.default
        if maxRotatedFiles <= 0 {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }

        let oldest = rotatedURL(maxRotatedFiles)
        if fileManager.fileExists(atPath: oldest.path) {
            try fileManager.removeItem(at: oldest)
        }

        if maxRotatedFiles > 1 {
            for index in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
                let source = rotatedURL(index)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: rotatedURL(index + 1))
            }
        }

        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.moveItem(at: fileURL, to: rotatedURL(1))
    }

    private func logURLs() -> [URL] {
        guard maxRotatedFiles > 0 else { return [fileURL] }
        return [fileURL] + (1 ... maxRotatedFiles).map(rotatedURL)
    }

    private func rotatedURL(_ index: Int) -> URL {
        URL(fileURLWithPath: "\(fileURL.path).\(index)")
    }

    private func fileSize(_ url: URL) throws -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue
    }

    private func setPrivateFilePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: FilePermissions.privateFile],
            ofItemAtPath: url.path
        )
    }
}

enum RemoteAuditLogError: LocalizedError {
    case invalidUTF8(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidUTF8(url):
            "Remote audit log contains invalid UTF-8 at \(url.path)."
        }
    }
}
