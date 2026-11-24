import Foundation
import CryptoKit
import OSLog

/// Owns persisted drawing metadata, not Core Data folder objects. Filesystem
/// enumeration runs in cancellable utility tasks; actor calls remain responsive.
actor LinkedFolderIndex {
    struct Root: Hashable, Sendable {
        let id: String
        let url: URL
        let bookmark: Data?
    }

    struct Update: Sendable {
        let recentFiles: [LinkedFolderScanner.Entry]
        let changedDirectories: [URL]
        let relocatedRoots: [String: URL]
        var invalidatedSubtrees: [URL] = []
        var indexChanged = false
        var revision: UInt64 = 0
    }

    private struct Snapshot: Codable {
        var version = 1
        let rootPath: String
        var files: [LinkedFolderScanner.Entry]
        var eventID: UInt64?
        var historyIdentity: String?
    }

    private struct Scope: Sendable {
        let url: URL
        let recursive: Bool
    }

    private struct ScanResult: Sendable {
        let scope: Scope
        let contents: LinkedFolderScanner.Result?
        let missing: Bool
    }

    private final class Session {
        let root: Root
        let access: LinkedFolderAccess
        let generation = UUID()
        var files: [URL: LinkedFolderScanner.Entry] = [:]
        var eventID: UInt64?
        var pendingEventID: UInt64 = 0
        var historyIdentity: String?
        var pending: [URL: Bool] = [:]
        var fullScan = false
        var worker: Task<Void, Never>?
        var debounce: Task<Void, Never>?
#if os(macOS)
        var monitor: LinkedFolderEventMonitor?
        var eventTask: Task<Void, Never>?
#endif

        init(root: Root, access: LinkedFolderAccess) {
            self.root = root
            self.access = access
        }

        func cancel() {
            worker?.cancel()
            debounce?.cancel()
#if os(macOS)
            eventTask?.cancel()
            monitor?.stop()
#endif
        }
    }

    private let cacheDirectory: URL
    private let publish: @Sendable (Update) async -> Void
    private let monitorsEvents: Bool
    private var sessions: [String: Session] = [:]
    private var configuredRoots: [Root] = []
    private var revision: UInt64 = 0
    private let logger = Logger(subsystem: "com.chocoford.excalidraw", category: "LinkedFolderIndex")

    init(cacheDirectory: URL, monitorsEvents: Bool = true,
         publish: @escaping @Sendable (Update) async -> Void = { _ in }) {
        self.cacheDirectory = cacheDirectory
        self.monitorsEvents = monitorsEvents
        self.publish = publish
    }

    func configure(_ roots: [Root]) async {
        guard !Task.isCancelled else { return }
        let rootsChanged = Set(configuredRoots) != Set(roots)
        configuredRoots = roots
        let configuredByID = Dictionary(roots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in Array(sessions.keys) where configuredByID[id] != sessions[id]?.root {
            sessions.removeValue(forKey: id)?.cancel()
            if configuredByID[id] == nil { try? FileManager.default.removeItem(at: cacheURL(id)) }
        }
        var selected = Set<String>()
        var selectedURLs: [URL] = []
        var relocated: [String: URL] = [:]
        for root in roots.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            // Collapse only roots whose parent grant is actually available. If
            // an outer bookmark fails, an independently authorized child still works.
            if selectedURLs.contains(where: { LinkedFolderScanner.visible(root.url, under: $0) }) { continue }
            if let existing = sessions[root.id] {
                selected.insert(root.id)
                selectedURLs.append(existing.root.url)
                continue
            }
            do {
                let access = try LinkedFolderAccess(url: root.url, bookmark: root.bookmark)
                let session = Session(root: root, access: access)
                sessions[root.id] = session
                selected.insert(root.id)
                selectedURLs.append(root.url)
                if access.url != root.url.standardizedFileURL { relocated[root.id] = access.url }
                if let data = try? Data(contentsOf: cacheURL(root.id)),
                   let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                   snapshot.version == 1, snapshot.rootPath == access.url.path {
                    for entry in snapshot.files where entry.url.isFileURL && LinkedFolderScanner.isDrawing(entry.url)
                        && LinkedFolderScanner.visible(entry.url, under: access.url) {
                        session.files[entry.url] = entry
                    }
                    session.eventID = snapshot.eventID
                    session.historyIdentity = snapshot.historyIdentity
                }
#if os(macOS)
                let identity = LinkedFolderEventMonitor.historyIdentity(at: access.url)
                let boundary = LinkedFolderEventMonitor.currentEventID
                let canReplay = identity != nil && identity == session.historyIdentity
                    && session.eventID.map { $0 <= boundary } == true
                session.historyIdentity = identity
                session.fullScan = !canReplay
                // A full scan starts with a known boundary; subsequent events stay pending.
                if session.fullScan { session.pendingEventID = boundary }
                if monitorsEvents {
                    do {
                        let since = canReplay ? session.eventID : (identity == nil ? nil : boundary)
                        let monitor = try LinkedFolderEventMonitor(url: access.url, since: since,
                                                                  excluding: [cacheDirectory])
                        session.monitor = monitor
                        let generation = session.generation
                        session.eventTask = Task { [weak self] in
                            for await batch in monitor.events {
                                guard !Task.isCancelled else { return }
                                await self?.receive(batch, rootID: root.id, generation: generation)
                            }
                        }
                    } catch {
                        // No reliable monitor means no reusable cursor. Fall back to a background scan.
                        session.fullScan = true
                        session.historyIdentity = nil
                        logger.error("Could not monitor linked folder: \(error.localizedDescription)")
                    }
                }
#else
                session.fullScan = true
#endif
            } catch {
                logger.error("Could not access linked folder: \(error.localizedDescription)")
            }
        }
        for id in Array(sessions.keys) where !selected.contains(id) {
            sessions.removeValue(forKey: id)?.cancel()
        }
        await emit(changed: [], relocated: relocated, indexChanged: rootsChanged)
        for id in sessions.keys { schedule(id, immediately: true) }
    }

    /// iOS file providers have no persistent FSEvents history. Their validation is
    /// also asynchronous and preserves the existing cache while materializing.
    func reconcile() {
        for (id, session) in sessions {
#if os(macOS)
            guard session.monitor == nil else { continue }
#endif
            session.fullScan = true
            schedule(id)
        }
    }

    func invalidate(_ urls: [URL], recursively: Bool = false) {
        for (id, session) in sessions {
            for url in urls where LinkedFolderScanner.visible(url, under: session.access.url) {
                session.pending[url.standardizedFileURL] = recursively || session.pending[url.standardizedFileURL] == true
            }
            schedule(id)
        }
    }

    func stop() async {
        for session in sessions.values { session.cancel() }
        sessions.removeAll()
        await emit(changed: [], indexChanged: true)
    }

    func drawingFiles(matching query: String = "", under root: URL? = nil) -> [LinkedFolderScanner.Entry] {
        var files: [URL: LinkedFolderScanner.Entry] = [:]
        for session in sessions.values {
            for entry in session.files.values where (root.map { LinkedFolderScanner.contains(entry.url, in: $0) } ?? true)
                && (query.isEmpty || entry.url.deletingPathExtension().lastPathComponent.contains(query)) {
                files[entry.url] = entry
            }
        }
        return files.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Internal entry point also used by deterministic event/relaunch regression tests.
    func receive(_ batch: LinkedFolderChangeBatch, rootID: String, generation: UUID? = nil) {
        guard let session = sessions[rootID], generation == nil || generation == session.generation else { return }
        session.pendingEventID = max(session.pendingEventID, batch.eventID)
        session.fullScan = session.fullScan || batch.requiresFullScan
        if batch.invalidatesHistory { session.historyIdentity = nil }
        if batch.rootChanged {
            let generation = session.generation
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                await self?.resolveChangedRoot(rootID, generation: generation)
            }
        }
        for url in batch.paths where LinkedFolderScanner.visible(url, under: session.access.url) {
            session.pending[url] = session.pending[url] == true || batch.recursivePaths.contains(url)
        }
        // Keep memory bounded during a build storm. A lost path always invalidates the cursor.
        if session.pending.count > 512 {
            session.pending.removeAll()
            session.fullScan = true
        }
        schedule(rootID)
    }

    private func schedule(_ id: String, immediately: Bool = false) {
        guard let session = sessions[id], session.worker == nil, session.debounce == nil,
              session.fullScan || !session.pending.isEmpty || session.pendingEventID > (session.eventID ?? 0) else { return }
        let generation = session.generation
        session.debounce = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await self?.startWork(id, generation: generation)
        }
    }

    private func startWork(_ id: String, generation: UUID) {
        guard let session = sessions[id], session.generation == generation else { return }
        session.debounce = nil
        guard sessions.values.filter({ $0.worker != nil }).count < 2 else { return }
        let fullScan = session.fullScan
        var scopes = fullScan ? [Scope(url: session.access.url, recursive: true)]
            : session.pending.map { Scope(url: $0.key, recursive: $0.value) }
        let recursiveRoots = LinkedFolderScanner.minimalRoots(scopes.filter(\.recursive).map(\.url))
        scopes = scopes.filter { scope in
            !recursiveRoots.contains { $0.path != scope.url.standardizedFileURL.path && LinkedFolderScanner.contains(scope.url, in: $0) }
        }
        let eventID = session.pendingEventID
        session.pending.removeAll()
        session.fullScan = false
        let access = session.access
        logger.debug("Linked folder scan scopes=\(scopes.count) full=\(fullScan)")
        session.worker = Task.detached(priority: .utility) { [weak self] in
            var results: [ScanResult] = []
            for scope in scopes {
                guard !Task.isCancelled else { return }
                let result: ScanResult = autoreleasepool {
                    do {
                        let contents = try LinkedFolderScanner.scan(scope.url, recursively: scope.recursive, onBatch: { batch in
                            Task { await self?.progress(id, generation: generation, entries: batch) }
                        })
                        return ScanResult(scope: scope, contents: contents, missing: false)
                    } catch {
                        let error = error as NSError
                        let missing = error.domain == NSCocoaErrorDomain
                            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
                        return ScanResult(scope: scope, contents: nil, missing: missing)
                    }
                }
                results.append(result)
            }
            withExtendedLifetime(access) {}
            guard !Task.isCancelled else { return }
            await self?.finish(id, generation: generation, results: results, eventID: eventID)
        }
    }

    private func finish(_ id: String, generation: UUID, results: [ScanResult], eventID: UInt64) async {
        guard let session = sessions[id], session.generation == generation else { return }
        session.worker = nil
        var complete = true
        var changed: Set<URL> = []
        var subtrees: Set<URL> = []
        for result in results {
            if result.missing && result.scope.url.path == session.access.url.path {
                // A disconnected volume/provider is not an empty linked root.
                complete = false
                continue
            }
            guard result.contents != nil || result.missing else {
                complete = false
                continue
            }
            let failed = result.contents?.unreadableDirectories ?? []
            if !failed.isEmpty { complete = false }
            session.files = session.files.filter { url, _ in
                let covered = result.scope.recursive || result.missing
                    ? LinkedFolderScanner.contains(url, in: result.scope.url)
                    : url.path == result.scope.url.path || url.deletingLastPathComponent().path == result.scope.url.path
                return !covered || failed.contains { LinkedFolderScanner.contains(url, in: $0) }
            }
            for entry in result.contents?.files ?? [] { session.files[entry.url] = entry }
            changed.insert(result.scope.url)
            changed.insert(result.scope.url.deletingLastPathComponent())
            if result.scope.recursive || result.missing { subtrees.insert(result.scope.url) }
        }
        // A failed scan cannot checkpoint past unreadable content, even if later
        // events are harmless. Revalidate on the next launch/manual refresh.
        if !complete { session.historyIdentity = nil }
        session.eventID = complete ? max(session.eventID ?? 0, eventID) : nil
        persist(session)
        await emit(changed: Array(changed), subtrees: Array(subtrees))
        for id in sessions.keys { schedule(id) }
    }

    private func progress(_ id: String, generation: UUID, entries: [LinkedFolderScanner.Entry]) async {
        guard let session = sessions[id], session.generation == generation, session.worker != nil else { return }
        for entry in entries { session.files[entry.url] = entry }
        // Partial discoveries are useful immediately, but never checkpoint an
        // incomplete traversal. Relaunch must still validate the complete tree.
        await emit(changed: [], indexChanged: true)
    }

    private func resolveChangedRoot(_ id: String, generation: UUID) async {
        guard let session = sessions[id], session.generation == generation,
              let access = try? LinkedFolderAccess(url: session.root.url, bookmark: session.root.bookmark),
              access.url != session.access.url else { return }
        let roots = configuredRoots.map { root in
            root.id == id ? Root(id: id, url: access.url, bookmark: root.bookmark) : root
        }
        await configure(roots)
        await emit(changed: [access.url], relocated: [id: access.url])
    }

    private func persist(_ session: Session) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let snapshot = Snapshot(rootPath: session.access.url.path, files: Array(session.files.values),
                                    eventID: session.eventID, historyIdentity: session.historyIdentity)
            try JSONEncoder().encode(snapshot).write(to: cacheURL(session.root.id), options: .atomic)
        } catch {
            logger.error("Could not save linked folder index: \(error.localizedDescription)")
        }
    }

    private func cacheURL(_ id: String) -> URL {
        let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name + ".json")
    }

    private func emit(changed: [URL], relocated: [String: URL] = [:], subtrees: [URL] = [], indexChanged: Bool = false) async {
        revision &+= 1
        var entries: [URL: LinkedFolderScanner.Entry] = [:]
        for session in sessions.values {
            entries.merge(session.files) { first, second in first.modifiedAt > second.modifiedAt ? first : second }
        }
        let recent = entries.values.sorted {
            $0.modifiedAt == $1.modifiedAt ? $0.url.path < $1.url.path : $0.modifiedAt > $1.modifiedAt
        }.prefix(20)
        await publish(Update(recentFiles: Array(recent), changedDirectories: changed,
                             relocatedRoots: relocated, invalidatedSubtrees: subtrees,
                             indexChanged: indexChanged, revision: revision))
    }
}
