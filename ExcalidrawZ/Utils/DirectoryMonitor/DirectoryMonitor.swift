//
//  DirectoryObserver.swift
//  Sparkling
//
//  Created by Dove Zachary on 2023/10/22.
//

import SwiftUI
import Combine
import os.log
import CoreServices

import ChocofordEssentials

@available(macOS 14.0, *)
@Observable
final class DirectoryObserver {
    private(set) var monitors: [DirectoryMonitor] = []
    
    let queue: DispatchQueue = .init(label: "DirectoryObserver")
    
    struct MonitorSource {
        let url: URL
        let object: DispatchSourceFileSystemObject
    }
    
    private var monitorSources: [MonitorSource] = []
    
    var anyChangedPublisher: PassthroughSubject<DirectoryMonitor.Event, Never> = .init()
    
    func addObservationDestination(url: URL, onEvent: @escaping (DirectoryMonitor.Event) -> Void = {_ in}) {
        let path = url.absoluteURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
//        do {
//            /*open(path, O_EVTONLY)*/
//            let fileDescriptor = try FileDescriptor.open(path, .readOnly)
//            let source = DispatchSource.makeFileSystemObjectSource(
//                fileDescriptor: fileDescriptor.rawValue,
//                eventMask: [.attrib],
//                queue: queue
//            )
//            source.setEventHandler {
//                DispatchQueue.main.async {
//                    self.anyChangedPublisher.send(url)
//                }
//            }
//            let monitorSource = MonitorSource(url: url, object: source)
//            monitorSources.append(monitorSource)
//            monitorSource.object.activate()
//            
//        } catch {
//            print("addObservationDestination failed: ", error, path)
//        }
        
        let monitor = DirectoryMonitor(url: url) { event in
            self.anyChangedPublisher.send(event)
            onEvent(event)
        }
        self.monitors.append(monitor)
    }
    
    func removeObservationDestination(url: URL) {
//        if let index = self.monitorSources.firstIndex(where: {$0.url == url}) {
//            let source = self.monitorSources.remove(at: index)
//            source.object.cancel()
//        }
        if let index = self.monitors.firstIndex(where: {$0.presentedItemURL == url}) {
            self.monitors.remove(at: index)
        }
    }
}

final class DirectoryObserverObject: ObservableObject {
    private(set) var monitors: [DirectoryMonitor] = []
    let queue: DispatchQueue = .init(label: "DirectoryObserver")
}

/**
public class DirectoryMonitor: NSObject, NSFilePresenter {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "DirectoryMonitor"
    )
    
    public lazy var presentedItemOperationQueue = OperationQueue.main
    public var presentedItemURL: URL?
    
    private var eventsQueue: EventsQueue = EventsQueue()
    
    init(url: URL, onEvents: @escaping (Event) async -> Void) {
        self.presentedItemURL = url
        super.init()
        self.start()
        Task {
            for await event in self.eventsQueue {
                logger.info("[DirectoryMonitor] on event: \(String(describing: event))")
                await onEvents(event)
            }
        }
    }
    
    deinit {
        self.stop()
    }
    
    public func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }
    
    public func start() {
        if NSFileCoordinator.filePresenters.contains(where: {
            $0.presentedItemURL == self.presentedItemURL
        }) {
            logger.warning("[DirectoryMonitor] start failed, reason: existed.")
            self.stop()
        }
        NSFileCoordinator.addFilePresenter(self)
        logger.info("[DirectoryMonitor] started observe '\(self.presentedItemURL?.absoluteString ?? "unknown")'")
    }
    
    public func presentedSubitemDidAppear(at url: URL) {
        guard let directoryURL = self.presentedItemURL else {
            logger.error("[DirectoryMonitor] presentedSubitemDidAppear error: presentedItemURL is nil")
            return
        }
        self.eventsQueue.yield(.subitemDidAppear(directoryURL, url))
        logger.info("[DirectoryMonitor] presentedSubitemDidAppear at \(url).")
    }
    
    public func presentedSubitemDidChange(at url: URL) {
        guard let directoryURL = self.presentedItemURL else {
            logger.error("[DirectoryMonitor] presentedSubitemDidChange error: presentedItemURL is nil")
            return
        }
        if let _ = try? FileManager.default.attributesOfItem(atPath: url.filePath) {
            self.eventsQueue.yield(.subitemDidChange(directoryURL, url))
        } else {
            self.eventsQueue.yield(.subitemDidLose(directoryURL, url, nil))
        }
        logger.info("[DirectoryMonitor] presentedSubitemDidChange at \(url).")
    }
    
    public func presentedSubitem(at url: URL, didLose version: NSFileVersion) {
        guard let directoryURL = self.presentedItemURL else {
            logger.error("[DirectoryMonitor] presentedSubitem error: presentedItemURL is nil")
            return
        }
        self.eventsQueue.yield(.subitemDidLose(directoryURL, url, version))
        logger.info("[DirectoryMonitor] presentedSubitem didLose at \(url).")
    }
    
    public func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        logger.info("[DirectoryMonitor] accommodatePresentedSubitemDeletion at \(url).")
    }
}

extension DirectoryMonitor {
    public enum Event {
        case subitemDidAppear(_ directoryURL: URL, _ url: URL)
        case subitemDidChange(_ directoryURL: URL, _ url: URL)
        case subitemDidLose(_ directoryURL: URL, _ url: URL, _ version: NSFileVersion?)
    }
    
    public typealias EventHandler = (Event) async -> Void
    
    public class EventsQueue: AsyncSequence {
        public typealias Element = DirectoryMonitor.Event
        private var continuation: AsyncStream<Element>.Continuation?
        
        public init() {}
        
        public func yield(_ event: Element) {
            continuation?.yield(event)
        }
        
        deinit {
            continuation?.finish()
        }
        
        public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
            return stream.makeAsyncIterator()
        }
        
        public lazy var stream: AsyncStream<Element> = {
             let stream = AsyncStream<Element> { c in
                 self.continuation = c
             }
             return stream
         }()
    }
}
*/



public class DirectoryMonitor {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "DirectoryMonitor"
    )
    
    private var eventStream: FSEventStreamRef?
    let presentedItemURL: URL
    private let eventHandler: (Event) -> Void

    public enum Event {
        case created(URL)
        case modified(URL)
        case deleted(URL)
    }

    public init(url: URL, eventHandler: @escaping (Event) -> Void) {
        self.presentedItemURL = url
        self.eventHandler = eventHandler
    }
    
    deinit {
        self.stop()
    }

    public func start() {
        // 获取目录路径
        let pathsToWatch = [presentedItemURL.filePath]
        
        // Create FSEventStreamContext
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let eventMask: FSEventStreamEventFlags = UInt32(
            kFSEventStreamEventFlagItemCreated |
            kFSEventStreamEventFlagItemModified |
            kFSEventStreamEventFlagItemRemoved
        )
        
        // Create the FSEventStream
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback, // Pass the callback function
            &context, // Pass the context by reference
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second delay for event detection
            eventMask // Use compatible flags
        )
        
        guard let eventStream = eventStream else {
            logger.error("[DirectoryMonitor] Failed to create event stream.")
            return
        }
        
        // Start monitoring
        FSEventStreamStart(eventStream)
        logger.info("[DirectoryMonitor] Started monitoring directory: \(String(describing: self.presentedItemURL.filePath))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            print("[DirectoryMonitor] Stream description: \(FSEventStreamCopyDescription(eventStream))")
        }
        
    }

    public func stop() {
        guard let eventStream = eventStream else {
            print("No event stream to stop.")
            return
        }

        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        print("Stopped monitoring directory: \(presentedItemURL.path)")
    }

    // FSEventStream callback with @convention(c)
    fileprivate func _eventCallback(
        _ streamRef: FSEventStreamRef,
        clientCallbackInfo: UnsafeMutableRawPointer?,
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<UInt32>,
        eventIds: UnsafePointer<UInt64>
    ) {
        let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<Int8>.self)
        
        for i in 0..<numEvents {
            let path = paths[i]
            let fileURL = URL(fileURLWithPath: String(cString: path))
            
            // 使用位掩码常量来检查事件标志
            if eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
                eventHandler(.created(fileURL))
                logger.info("[DirectoryMonitor] file<\(fileURL)> did created")
            } else if eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
                eventHandler(.modified(fileURL))
                logger.info("[DirectoryMonitor] file<\(fileURL)> did modified")
            } else if eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
                eventHandler(.deleted(fileURL))
                logger.info("[DirectoryMonitor] file<\(fileURL)> did removed")
            } else {
                logger.warning("[DirectoryMonitor] Unknwon file event.")
            }
        }
    }
}

// Wrap the callback with @convention(c)
private let eventCallback: @convention(c) (
    FSEventStreamRef,
    UnsafeMutableRawPointer?,
    Int,
    UnsafeMutableRawPointer,
    UnsafePointer<UInt32>,
    UnsafePointer<UInt64>
) -> Void = { streamRef, clientCallbackInfo, numEvents, eventPaths, eventFlags, eventIds in
    // Access your DirectoryMonitor instance here
    let monitor = Unmanaged<DirectoryMonitor>.fromOpaque(clientCallbackInfo!).takeUnretainedValue()
    monitor._eventCallback(
        streamRef,
        clientCallbackInfo: clientCallbackInfo,
        numEvents: numEvents,
        eventPaths: eventPaths,
        eventFlags: eventFlags,
        eventIds: eventIds
    )
}
