import Foundation
import MuxyShared
import Testing

@testable import Muxy

@Suite("RemoteAuditLog")
struct RemoteAuditLogTests {
    private func tempLogURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteAuditLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("remote.log")
    }

    private func record(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        timestamp: Date = Date(timeIntervalSince1970: 1_800_000_000),
        clientID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        deviceID: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        deviceName: String? = "Swaylen's iPhone",
        method: MuxyMethod = .vcsPush,
        projectID: UUID? = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        argsSummary: String = "projectID=33333333-3333-3333-3333-333333333333",
        outcome: RemoteAuditRecord.Outcome = .succeeded,
        errorMessage: String? = nil,
        nonce: String? = nil,
        serverTimestamp: Int64? = nil
    ) -> RemoteAuditRecord {
        RemoteAuditRecord(
            id: id,
            timestamp: timestamp,
            clientID: clientID,
            deviceID: deviceID,
            deviceName: deviceName,
            method: method,
            projectID: projectID,
            argsSummary: argsSummary,
            outcome: outcome,
            errorMessage: errorMessage,
            nonce: nonce,
            serverTimestamp: serverTimestamp
        )
    }

    @Test("append writes one JSON line and recent decodes it")
    func appendWritesJSONLineAndRecentDecodesIt() throws {
        let url = try tempLogURL()
        let log = RemoteAuditLog(fileURL: url, maxBytes: 4_096, maxRotatedFiles: 5)
        let entry = record()

        try log.append(entry)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 1)
        #expect(text.hasSuffix("\n"))
        #expect(try log.recent(limit: 10) == [entry])
    }

    @Test("append preserves every record as a separate line")
    func appendPreservesRecordsAsSeparateLines() throws {
        let url = try tempLogURL()
        let log = RemoteAuditLog(fileURL: url, maxBytes: 4_096, maxRotatedFiles: 5)
        let first = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_001),
            argsSummary: "projectID=33333333-3333-3333-3333-333333333333"
        )
        let second = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: Date(timeIntervalSince1970: 1_800_000_002),
            method: .vcsDiscardFiles,
            argsSummary: "projectID=33333333-3333-3333-3333-333333333333 paths=2 untrackedPaths=1",
            outcome: .failed,
            errorMessage: "discard failed"
        )

        try log.append(first)
        try log.append(second)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2)
        #expect(try log.recent(limit: 10) == [second, first])
    }

    @Test("rotation keeps active log plus configured rotated files")
    func rotationKeepsConfiguredFileCount() throws {
        let url = try tempLogURL()
        let log = RemoteAuditLog(fileURL: url, maxBytes: 700, maxRotatedFiles: 5)

        for index in 0 ..< 9 {
            let paddedSummary = "entry-\(index) " + String(repeating: "x", count: 160)
            try log.append(record(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                argsSummary: paddedSummary
            ))
        }

        let directory = url.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 == "remote.log" || $0.hasPrefix("remote.log.") }
            .sorted()

        #expect(files.contains("remote.log"))
        #expect(files.contains("remote.log.1"))
        #expect(!files.contains("remote.log.6"))
        #expect(files.count <= 6)
        #expect(try log.recent(limit: 3).map(\.argsSummary).map { $0.prefix(7) } == ["entry-8", "entry-7", "entry-6"])
    }

    @Test("recent supports disabled rotated file reads")
    func recentSupportsDisabledRotatedFileReads() throws {
        let url = try tempLogURL()
        let log = RemoteAuditLog(fileURL: url, maxBytes: 4_096, maxRotatedFiles: 0)
        let entry = record()

        try log.append(entry)

        #expect(try log.recent(limit: 10) == [entry])
    }
}
