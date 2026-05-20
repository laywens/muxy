import CoreServices
import Foundation

protocol FileSystemWatching: AnyObject {}

struct FileSystemWatcherEvent: Equatable {
    let path: String
    let isDirectory: Bool
}

final class FileSystemWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.muxy.fs-watcher", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var handler: (@Sendable ([FileSystemWatcherEvent]) -> Void)?
    private var pendingEvents: [FileSystemWatcherEvent] = []

    convenience init?(directoryPath: String, handler: @escaping @Sendable () -> Void) {
        self.init(directoryPath: directoryPath) { _ in handler() }
    }

    init?(directoryPath: String, handler: @escaping @Sendable ([FileSystemWatcherEvent]) -> Void) {
        guard FileManager.default.fileExists(atPath: directoryPath) else { return nil }

        queue.setSpecific(key: queueKey, value: true)
        self.handler = handler

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directoryPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
                guard let clientInfo, numEvents > 0 else { return }
                DiagnosticsCounters.shared.recordFSEvents(eventCount: numEvents)
                let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
                else { return }
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                let events = zip(paths, flags).map { path, flag in
                    FileSystemWatcherEvent(
                        path: path,
                        isDirectory: flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
                    )
                }
                let dominated = events.allSatisfy { event in
                    let path = event.path
                    let isGitInternal = path.contains("/.git/")
                    let isLockFile = path.hasSuffix(".lock")
                    return isGitInternal && isLockFile || event.isDirectory && isGitInternal
                }
                guard !dominated else { return }

                watcher.scheduleRefresh(events)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
        DiagnosticsCounters.shared.recordFSEventStreamStarted()
    }

    deinit {
        Self.performSerializedTeardown(on: queue, key: queueKey) {
            handler = nil
            debounceWork?.cancel()
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            DiagnosticsCounters.shared.recordFSEventStreamStopped()
        }
    }

    private func scheduleRefresh(_ events: [FileSystemWatcherEvent]) {
        pendingEvents.append(contentsOf: events)
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DiagnosticsCounters.shared.recordWatcherRefresh()
            let events = pendingEvents
            pendingEvents.removeAll()
            handler?(events)
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    static func performSerializedTeardown(
        on queue: DispatchQueue,
        key: DispatchSpecificKey<some Sendable>,
        _ action: () -> Void
    ) {
        if DispatchQueue.getSpecific(key: key) != nil {
            action()
            return
        }
        queue.sync(execute: action)
    }
}

extension FileSystemWatcher: FileSystemWatching {}
