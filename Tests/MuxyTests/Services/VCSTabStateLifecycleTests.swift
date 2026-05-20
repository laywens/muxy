import Foundation
import Testing

@testable import Muxy

@Suite("VCSTabState lifecycle", .serialized)
@MainActor
struct VCSTabStateLifecycleTests {
    @Test("active states share injected repo activity monitor watcher")
    func activeStatesShareInjectedRepoActivityMonitorWatcher() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcherProbe = TestRepoActivityWatcherProbe()
        let monitor = RepoActivityMonitor(watcherFactory: watcherProbe.makeWatcher)
        let first = VCSTabState(
            projectPath: root.path,
            activityMonitor: monitor,
            notificationCenter: NotificationCenter()
        )
        let second = VCSTabState(
            projectPath: root.appendingPathComponent(".").path,
            activityMonitor: monitor,
            notificationCenter: NotificationCenter()
        )

        first.activate(reason: .visibleTab)
        second.activate(reason: .attachedPanel)

        #expect(watcherProbe.createdPaths == [root.path])
        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        first.deactivate(reason: .visibleTab)

        #expect(watcherProbe.liveCount == 1)
        #expect(monitor.activeRootCount == 1)

        second.deactivate(reason: .attachedPanel)

        #expect(watcherProbe.liveCount == 0)
        #expect(monitor.activeRootCount == 0)
    }

    @Test("new state does not install watcher until activated")
    func newStateDoesNotInstallWatcherUntilActivated() {
        let counter = WatcherCounter()
        let state = VCSTabState(
            projectPath: tempPath(),
            watcherFactory: counter.makeWatcher,
            notificationCenter: NotificationCenter()
        )

        #expect(counter.liveCount == 0)
        #expect(!state.isActive)

        state.activate(reason: .visibleTab)

        #expect(counter.liveCount == 1)
        #expect(state.isActive)

        state.deactivate(reason: .visibleTab)

        #expect(counter.liveCount == 0)
        #expect(!state.isActive)
    }

    @Test("multiple activation reasons share one watcher")
    func multipleActivationReasonsShareOneWatcher() {
        let counter = WatcherCounter()
        let state = VCSTabState(
            projectPath: tempPath(),
            watcherFactory: counter.makeWatcher,
            notificationCenter: NotificationCenter()
        )

        state.activate(reason: .visibleTab)
        state.activate(reason: .attachedPanel)

        #expect(counter.createdCount == 1)
        #expect(counter.liveCount == 1)
        #expect(state.isActive)

        state.deactivate(reason: .visibleTab)

        #expect(counter.liveCount == 1)
        #expect(state.isActive)

        state.deactivate(reason: .attachedPanel)

        #expect(counter.liveCount == 0)
        #expect(!state.isActive)
    }

    @Test("matching activation reasons are reference counted")
    func matchingActivationReasonsAreReferenceCounted() {
        let counter = WatcherCounter()
        let state = VCSTabState(
            projectPath: tempPath(),
            watcherFactory: counter.makeWatcher,
            notificationCenter: NotificationCenter()
        )

        state.activate(reason: .visibleTab)
        state.activate(reason: .visibleTab)

        #expect(counter.createdCount == 1)
        #expect(counter.liveCount == 1)
        #expect(state.isActive)

        state.deactivate(reason: .visibleTab)

        #expect(counter.liveCount == 1)
        #expect(state.isActive)

        state.deactivate(reason: .visibleTab)

        #expect(counter.liveCount == 0)
        #expect(!state.isActive)
    }

    @Test("refreshOnDemand does not activate background watcher")
    func refreshOnDemandDoesNotActivateBackgroundWatcher() async throws {
        let repo = try TempGitRepo()
        defer { repo.cleanup() }

        let counter = WatcherCounter()
        let state = VCSTabState(
            projectPath: repo.path,
            watcherFactory: counter.makeWatcher,
            notificationCenter: NotificationCenter()
        )

        await state.refreshOnDemand()

        #expect(counter.createdCount == 0)
        #expect(counter.liveCount == 0)
        #expect(!state.isActive)
        #expect(state.hasCompletedInitialLoad)
    }

    @Test("auto sync deadline survives activation flips")
    func autoSyncDeadlineSurvivesActivationFlips() async throws {
        let probe = AutoSyncProbe()
        let state = VCSTabState(
            projectPath: tempPath(),
            watcherFactory: WatcherCounter().makeWatcher,
            notificationCenter: NotificationCenter(),
            autoSyncNanosecondsPerMinute: 300_000_000,
            pullRequestAutoSyncAction: { _ in probe.record() }
        )

        state.setPullRequestAutoSyncMinutes(1)
        state.activate(reason: .visibleTab)
        try await Task.sleep(nanoseconds: 200_000_000)
        state.deactivate(reason: .visibleTab)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(probe.count == 0)

        state.activate(reason: .visibleTab)
        try await probe.waitForCount(1)
        state.deactivate(reason: .visibleTab)
    }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-vcs-lifecycle-\(UUID().uuidString)", isDirectory: true)
            .path
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-vcs-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class WatcherCounter {
    private(set) var createdCount = 0
    private(set) var liveCount = 0

    func makeWatcher(
        directoryPath _: String,
        handler _: @escaping @Sendable () -> Void
    ) -> (any FileSystemWatching)? {
        createdCount += 1
        liveCount += 1
        return CountingWatcher { [weak self] in
            self?.liveCount -= 1
        }
    }
}

private final class CountingWatcher: FileSystemWatching {
    private let onDeinit: () -> Void

    init(onDeinit: @escaping () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }
}

private final class AutoSyncProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var fireCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return fireCount
    }

    func record() {
        lock.lock()
        fireCount += 1
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pending {
            continuation.resume()
        }
    }

    func waitForCount(_ expected: Int) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.lock.lock()
                    if self.fireCount >= expected {
                        self.lock.unlock()
                        continuation.resume()
                        return
                    }
                    self.continuations.append(continuation)
                    self.lock.unlock()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 250_000_000)
                throw NSError(domain: "AutoSyncProbe", code: 1)
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

private struct TempGitRepo {
    let path: String
    private let parent: String

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-vcs-lifecycle-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        parent = root.path
        path = root.appendingPathComponent("repo", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Self.runGit(at: path, args: ["init", "-q", "-b", "main"])
        try Self.runGit(at: path, args: ["config", "user.email", "test@example.com"])
        try Self.runGit(at: path, args: ["config", "user.name", "Test"])
        try Self.runGit(at: path, args: ["config", "commit.gpgsign", "false"])
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try Self.runGit(at: path, args: ["add", "README.md"])
        try Self.runGit(at: path, args: ["commit", "-q", "-m", "initial"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: parent)
    }

    private static func runGit(at workingDir: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", workingDir] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "TempGitRepo",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""]
            )
        }
    }
}
