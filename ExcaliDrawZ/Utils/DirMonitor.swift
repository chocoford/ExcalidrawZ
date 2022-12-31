//
//  DirMonitor.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation
import OSLog
import Combine

class DirMonitor {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DirMonitor")
    init(dir: URL, queue: DispatchQueue) {
        self.dir = dir
        self.queue = queue
    }
    
    let dirWillChange: CurrentValueSubject<[(url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId)], Never> = .init([])

    deinit {
        // The stream has a reference to us via its `info` pointer. If the
        // client releases their reference to us without calling `stop`, that
        // results in a dangling pointer. We detect this as a programming error.
        // There are other approaches to take here (for example, messing around
        // with weak, or forming a retain cycle that’s broken on `stop`), but
        // this approach:
        //
        // * Has clear rules
        // * Is easy to implement
        // * Generate a sensible debug message if the client gets things wrong
        precondition(self.stream == nil, "released a running monitor")
        // I added this log line as part of my testing of the deallocation path.
        logger.info("did deinit")
    }

    let dir: URL
    let queue: DispatchQueue

    private var stream: FSEventStreamRef? = nil

    func start() -> Bool {
        precondition(self.stream == nil, "started a running monitor")

        // Set up our context.
        //
        // `FSEventStreamCallback` is a C function, so we pass `self` to the
        // `info` pointer so that it get call our `handleUnsafeEvents(…)`
        // method.  This involves the standard `Unmanaged` dance:
        //
        // * Here we set `info` to an unretained pointer to `self`.
        // * Inside the function we extract that pointer as `obj` and then use
        //   that to call `handleUnsafeEvents(…)`.

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        // Create the stream.
        //
        // In this example I wanted to show how to deal with raw string paths,
        // so I’m not taking advantage of `kFSEventStreamCreateFlagUseCFTypes`
        // or the even cooler `kFSEventStreamCreateFlagUseExtendedData`.

        guard let stream = FSEventStreamCreate(nil, { (stream, info, numEvents, eventPaths, eventFlags, eventIds) in
                let obj = Unmanaged<DirMonitor>.fromOpaque(info!).takeUnretainedValue()
                obj.handleUnsafeEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags, eventIDs: eventIds)
            },
            &context,
            [self.dir.path as NSString] as NSArray,
            UInt64(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return false
        }
        self.stream = stream

        // Now that we have a stream, schedule it on our target queue.

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            self.stream = nil
            return false
        }
        return true
    }

    private func handleUnsafeEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIDs: UnsafePointer<FSEventStreamEventId>) {
        // This takes the low-level goo from the C callback, converts it to
        // something that makes sense for Swift, and then passes that to
        // `handle(events:…)`.
        //
        // Note that we don’t need to do any rebinding here because this data is
        // coming C as the right type.
        let pathsBase = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let pathsBuffer = UnsafeBufferPointer(start: pathsBase, count: numEvents)
        let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: numEvents)
        let eventIDsBuffer = UnsafeBufferPointer(start: eventIDs, count: numEvents)
        // As `zip(_:_:)` only handles two sequences, I map over the index.
        let events = (0..<numEvents).map { i -> (url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId) in
            let path = pathsBuffer[i]
            // We set `isDirectory` to true because we only generate directory
            // events (that is, we don’t pass
            // `kFSEventStreamCreateFlagFileEvents` to `FSEventStreamCreate`.
            // This is generally the best way to use FSEvents, but if you decide
            // to take advantage of `kFSEventStreamCreateFlagFileEvents` then
            // you’ll need to code to `isDirectory` correctly.
            let url: URL = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
            return (url, flagsBuffer[i], eventIDsBuffer[i])
        }
        self.handle(events: events)
    }

    private func handle(events: [(url: URL, flags: FSEventStreamEventFlags, eventIDs: FSEventStreamEventId)]) {
        // In this example we just print the events with get, prefixed by a
        // count so that we can see the batching in action.
        logger.info("file changed.")
        dirWillChange.send(events)
    }

    func stop() {
        guard let stream = self.stream else {
            return          // We accept redundant calls to `stop`.
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }
}
