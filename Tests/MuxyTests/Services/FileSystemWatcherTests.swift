import Foundation
import Testing

@testable import Muxy

@Suite("FileSystemWatcher")
struct FileSystemWatcherTests {
    @Test("serialized teardown drains queued watcher work")
    func serializedTeardownDrainsQueuedWatcherWork() {
        let queue = DispatchQueue(label: "test.muxy.file-system-watcher")
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let recorder = LockedRecorder()

        queue.async {
            recorder.append("callback")
        }

        FileSystemWatcher.performSerializedTeardown(on: queue, key: key) {
            recorder.append("teardown")
        }

        #expect(recorder.values == ["callback", "teardown"])
    }

    @Test("serialized teardown runs inline on watcher queue")
    func serializedTeardownRunsInlineOnWatcherQueue() throws {
        let queue = DispatchQueue(label: "test.muxy.file-system-watcher-inline")
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let recorder = LockedRecorder()
        let finished = DispatchSemaphore(value: 0)

        queue.async {
            FileSystemWatcher.performSerializedTeardown(on: queue, key: key) {
                recorder.append("teardown")
            }
            finished.signal()
        }

        #expect(finished.wait(timeout: .now() + 1) == .success)
        #expect(recorder.values == ["teardown"])
    }
}

private final class LockedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: String) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
