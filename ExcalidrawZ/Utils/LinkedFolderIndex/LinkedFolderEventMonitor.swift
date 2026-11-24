import Foundation
#if os(macOS)
import CoreServices
import Darwin
#endif

struct LinkedFolderChangeBatch: Sendable {
    var paths: [URL] = []
    var recursivePaths: Set<URL> = []
    var eventID: UInt64 = 0
    var requiresFullScan = false
    var rootChanged = false
    var invalidatesHistory = false
}

#if os(macOS)
/// Keeps the complete callback batch together so a checkpoint never jumps over an
/// unprocessed event. This also receives directory moves and historical events.
final class LinkedFolderEventMonitor: @unchecked Sendable {
    private final class Context {
        let continuation: AsyncStream<LinkedFolderChangeBatch>.Continuation
        let root: URL
        let canonicalRootPath: String
        let excludedPaths: [String]
        init(_ continuation: AsyncStream<LinkedFolderChangeBatch>.Continuation, root: URL, excluding: [URL]) {
            self.continuation = continuation
            self.root = root
            // FSEvents uses physical paths (/private/var), while Foundation may
            // canonicalize an existing path differently from a deleted one.
            if let path = realpath(root.path, nil) {
                canonicalRootPath = String(cString: path)
                free(path)
            } else {
                canonicalRootPath = root.path
            }
            let physicalRootPath = canonicalRootPath
            excludedPaths = excluding.flatMap { url -> [String] in
                var paths = [url.path]
                if url.path.hasPrefix(root.path + "/") {
                    paths.append(physicalRootPath + url.path.dropFirst(root.path.count))
                }
                guard let resolved = realpath(url.path, nil) else { return paths }
                defer { free(resolved) }
                return paths + [String(cString: resolved)]
            }
        }

        func logicalURL(for path: String) -> URL {
            guard path == canonicalRootPath || path.hasPrefix(canonicalRootPath + "/") else {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            let relative = path.dropFirst(canonicalRootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? root : root.appendingPathComponent(relative)
        }
    }

    let events: AsyncStream<LinkedFolderChangeBatch>
    private var stream: FSEventStreamRef?

    static var currentEventID: UInt64 { FSEventsGetCurrentEventId() }

    static func historyIdentity(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let uuid = FSEventsCopyUUIDForDevice(dev_t(device.int32Value)) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    init(url: URL, since eventID: UInt64?, excluding: [URL] = []) throws {
        let pair = AsyncStream<LinkedFolderChangeBatch>.makeStream()
        events = pair.stream
        let box = Context(pair.continuation, root: url, excluding: excluding)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Context>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            },
            release: { pointer in
                if let pointer { Unmanaged<Context>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            nil, Self.callback, &context, [url.path] as CFArray,
            eventID ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
        ) else { throw CocoaError(.fileReadUnknown) }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "LinkedFolderIndex.events", qos: .utility))
        guard FSEventStreamStart(stream) else {
            stop()
            throw CocoaError(.fileReadUnknown)
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit { stop() }

    private static let callback: FSEventStreamCallback = { _, info, count, pathsPointer, flags, ids in
        guard let info,
              let paths = unsafeBitCast(pathsPointer, to: CFArray.self) as? [String] else { return }
        let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
        var batch = LinkedFolderChangeBatch()
        let invalidFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        )
        for index in 0..<count {
            let flag = flags[index]
            if context.excludedPaths.contains(where: { paths[index] == $0 || paths[index].hasPrefix($0 + "/") }) {
                // Linking the home directory must not turn checkpoint writes
                // into a permanent write -> FSEvent -> checkpoint feedback loop.
                continue
            }
            batch.eventID = max(batch.eventID, ids[index])
            if flag & invalidFlags != 0 { batch.requiresFullScan = true }
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
                batch.invalidatesHistory = true
            }
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                batch.rootChanged = true
                batch.requiresFullScan = true
            }
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
            let url = context.logicalURL(for: paths[index])
            let isDirectory = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
            let isFile = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0
            // Regular build outputs still advance the cursor, but never enter the index.
            if isDirectory || (!isFile && !LinkedFolderScanner.isDrawing(url)) || LinkedFolderScanner.isDrawing(url) {
                batch.paths.append(url)
                let subtreeChanged = FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemRemoved
                )
                if isDirectory && flag & subtreeChanged != 0 { batch.recursivePaths.insert(url) }
            }
        }
        if batch.eventID != 0 || batch.requiresFullScan || !batch.paths.isEmpty {
            context.continuation.yield(batch)
        }
    }
}
#endif
