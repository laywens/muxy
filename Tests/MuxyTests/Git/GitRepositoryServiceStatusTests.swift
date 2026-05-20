import Foundation
import Testing

@testable import Muxy

@Suite("GitRepositoryService status")
struct GitRepositoryServiceStatusTests {
    @Test("quickStatus uses status only and leaves stats unloaded")
    func quickStatusUsesStatusOnly() async throws {
        let statusOutput = " M tracked.swift\0?? new.txt\0"
        let recorder = GitRunnerRecorder(results: [
            GitProcessResult(
                status: 0,
                stdout: "true\n",
                stdoutData: Data("true\n".utf8),
                stderr: "",
                truncated: false
            ),
            GitProcessResult(
                status: 0,
                stdout: statusOutput,
                stdoutData: Data(statusOutput.utf8),
                stderr: "",
                truncated: false
            ),
        ])
        let service = GitRepositoryService(runGit: recorder.runGit)

        let files = try await service.quickStatus(repoPath: "/tmp/muxy-status-\(UUID().uuidString)")

        #expect(await recorder.arguments == [
            ["rev-parse", "--is-inside-work-tree"],
            ["-c", "core.quotepath=false", "status", "--porcelain=1", "-z", "--untracked-files=all"],
        ])
        #expect(files.map(\.path) == ["new.txt", "tracked.swift"])
        #expect(files.first { $0.path == "new.txt" }?.additions == nil)
        #expect(files.first { $0.path == "tracked.swift" }?.deletions == nil)
    }

    @Test("detailedDiff loads stats through the diff tier")
    func detailedDiffLoadsStatsThroughDiffTier() async throws {
        let patch = """
        diff --git a/tracked.swift b/tracked.swift
        @@ -1 +1,2 @@
        -old
        +new
        +line
        """
        let recorder = GitRunnerRecorder(results: [
            GitProcessResult(
                status: 0,
                stdout: patch,
                stdoutData: Data(patch.utf8),
                stderr: "",
                truncated: false
            ),
        ])
        let service = GitRepositoryService(runGit: recorder.runGit)

        let result = try await service.detailedDiff(
            repoPath: "/tmp/muxy-diff-\(UUID().uuidString)",
            filePath: "tracked.swift",
            hints: GitRepositoryService.DiffHints(hasStaged: false, hasUnstaged: true, isUntrackedOrNew: false),
            lineLimit: 20_000
        )

        #expect(await recorder.arguments == [
            ["-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff", "--", "tracked.swift"],
        ])
        #expect(result.additions == 2)
        #expect(result.deletions == 1)
    }

    @Test("untracked detailed diff caps large files")
    func untrackedDetailedDiffCapsLargeFiles() async throws {
        let repo = try TempStatusRepo()
        defer { repo.cleanup() }
        try repo.write(path: "large.txt", data: Data(repeating: 0x61, count: 2_097_153))

        let result = try await GitRepositoryService().detailedDiff(
            repoPath: repo.path,
            filePath: "large.txt",
            hints: GitRepositoryService.DiffHints(hasStaged: false, hasUnstaged: false, isUntrackedOrNew: true),
            lineLimit: 20_000
        )

        #expect(result.truncated)
        #expect(result.rows.isEmpty)
        #expect(result.additions == 0)
        #expect(result.deletions == 0)
    }

    @Test("untracked detailed diff skips generated paths")
    func untrackedDetailedDiffSkipsGeneratedPaths() async throws {
        let repo = try TempStatusRepo()
        defer { repo.cleanup() }
        try repo.write(path: ".build/generated.swift", contents: "let value = 1\n")

        let result = try await GitRepositoryService().detailedDiff(
            repoPath: repo.path,
            filePath: ".build/generated.swift",
            hints: GitRepositoryService.DiffHints(hasStaged: false, hasUnstaged: false, isUntrackedOrNew: true),
            lineLimit: 20_000
        )

        #expect(!result.truncated)
        #expect(result.rows.isEmpty)
        #expect(result.additions == 0)
        #expect(result.deletions == 0)
    }

    @Test("untracked detailed diff skips binary-looking content")
    func untrackedDetailedDiffSkipsBinaryContent() async throws {
        let repo = try TempStatusRepo()
        defer { repo.cleanup() }
        try repo.write(path: "image.bin", data: Data([0, 1, 2, 3, 4]))

        let result = try await GitRepositoryService().detailedDiff(
            repoPath: repo.path,
            filePath: "image.bin",
            hints: GitRepositoryService.DiffHints(hasStaged: false, hasUnstaged: false, isUntrackedOrNew: true),
            lineLimit: 20_000
        )

        #expect(!result.truncated)
        #expect(result.rows.isEmpty)
        #expect(result.additions == 0)
        #expect(result.deletions == 0)
    }
}

private actor GitRunnerRecorder {
    private var queuedResults: [GitProcessResult]
    private var recordedArguments: [[String]] = []

    var arguments: [[String]] {
        recordedArguments
    }

    init(results: [GitProcessResult]) {
        queuedResults = results
    }

    func runGit(
        repoPath _: String,
        arguments: [String],
        lineLimit _: Int?,
        timeout _: TimeInterval?
    ) async throws -> GitProcessResult {
        recordedArguments.append(arguments)
        guard !queuedResults.isEmpty else {
            throw NSError(domain: "GitRunnerRecorder", code: 1)
        }
        return queuedResults.removeFirst()
    }
}

private struct TempStatusRepo {
    let path: String
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-status-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        path = root.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(path relativePath: String, contents: String) throws {
        try write(path: relativePath, data: Data(contents.utf8))
    }

    func write(path relativePath: String, data: Data) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}
