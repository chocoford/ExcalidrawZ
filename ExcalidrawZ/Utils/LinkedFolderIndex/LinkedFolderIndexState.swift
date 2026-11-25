import Foundation
import CoreData
import Observation

extension Notification.Name {
    static let linkedFolderContentsDidChange = Notification.Name("linkedFolderContentsDidChange")
}

/// The sidebar and Home share bounded refresh queues and one private context,
/// avoiding duplicate child records and a Dispatch queue for every folder.
actor LinkedFolderDirectoryLoader {
    static let shared = LinkedFolderDirectoryLoader()
    private let queue = LinkedFolderRefreshQueue<String, Void>(maximumConcurrent: 1)
    private let filesQueue = LinkedFolderRefreshQueue<String, [LinkedFolderScanner.Entry]?>(maximumConcurrent: 1)
    private let countsQueue = LinkedFolderRefreshQueue<String, Int?>(maximumConcurrent: 1)
    private lazy var context = PersistenceController.shared.newTaskContext()

    func refresh(_ folderID: NSManagedObjectID) async throws {
        let context = self.context
        try await queue.run(key: folderID.uriRepresentation().absoluteString, requiresFreshResult: true) {
            let cancellation = LinkedFolderScanCancellation()
            try await withTaskCancellationHandler {
                try await context.perform {
                    // One shared private queue handles all levels. Never create
                    // a private context/Dispatch queue for every visible folder.
                    defer { context.reset() }
                    guard !cancellation.isCancelled,
                          let folder = try context.existingObject(with: folderID) as? LocalFolder,
                          !folder.isDeleted else { return }
                    try folder.refreshChildren(context: context, recursively: false, cancellation: cancellation)
                }
            } onCancel: { cancellation.cancel() }
        }
    }

    func files(in folderID: NSManagedObjectID) async throws -> [LinkedFolderScanner.Entry]? {
        let context = self.context
        return try await filesQueue.run(key: folderID.uriRepresentation().absoluteString, requiresFreshResult: true) {
            let cancellation = LinkedFolderScanCancellation()
            return try await withTaskCancellationHandler {
                try await context.perform {
                    defer { context.reset() }
                    guard !cancellation.isCancelled,
                          let folder = try context.existingObject(with: folderID) as? LocalFolder,
                          !folder.isDeleted else { return nil }
                    return try folder.withSecurityScopedURL { url in
                        let result = try LinkedFolderScanner.scan(url, recursively: false, isCancelled: { cancellation.isCancelled })
                        return result.unreadableDirectories.isEmpty ? result.files : nil
                    }
                }
            } onCancel: { cancellation.cancel() }
        }
    }

    func itemCount(in folderID: NSManagedObjectID) async throws -> Int? {
        let context = self.context
        return try await countsQueue.run(key: folderID.uriRepresentation().absoluteString, requiresFreshResult: true) {
            let cancellation = LinkedFolderScanCancellation()
            return try await withTaskCancellationHandler {
                try await context.perform {
                    defer { context.reset() }
                    guard !cancellation.isCancelled,
                          let folder = try context.existingObject(with: folderID) as? LocalFolder,
                          !folder.isDeleted else { return nil }
                    return try folder.withSecurityScopedURL { url in
                        try LinkedFolderScanner.immediateItemCount(at: url) { cancellation.isCancelled }
                    }
                }
            } onCancel: { cancellation.cancel() }
        }
    }

    func cancel(_ folderIDs: [NSManagedObjectID]) async {
        let keys = folderIDs.map { $0.uriRepresentation().absoluteString }
        await queue.cancel(keys: keys)
        await filesQueue.cancel(keys: keys)
        await countsQueue.cancel(keys: keys)
    }

}

extension LinkedFolderIndex {
    static let shared = LinkedFolderIndex(
        cacheDirectory: URL.cachesDirectory.appendingPathComponent("LinkedFolderIndex", isDirectory: true)
    ) { update in
        await LinkedFolderIndexState.shared.apply(update)
    }
}

/// Only the small recent-file projection is observed by Home. Browsers receive
/// scoped invalidations without subscribing to the complete filesystem index.
@MainActor
@Observable
final class LinkedFolderIndexState {
    static let shared = LinkedFolderIndexState()
    private(set) var recentFiles: [LinkedFolderScanner.Entry] = []
    @ObservationIgnored private var appliedRevision: UInt64 = 0
    @ObservationIgnored private var configurationGeneration = 0
    @ObservationIgnored private var rootRefreshTask: Task<Void, Never>?

    static func configureFromPersistence() async {
        guard !Task.isCancelled else { return }
        shared.configurationGeneration &+= 1
        let generation = shared.configurationGeneration
        let context = PersistenceController.shared.newTaskContext()
        let roots = try? await context.perform { () throws -> [LinkedFolderIndex.Root] in
            let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            request.predicate = NSPredicate(format: "parent == nil")
            return try context.fetch(request).compactMap { folder in
                folder.url.map { LinkedFolderIndex.Root(
                    id: folder.objectID.uriRepresentation().absoluteString,
                    url: $0, bookmark: folder.bookmarkData
                ) }
            }
        }
        guard !Task.isCancelled, generation == shared.configurationGeneration, let roots else { return }
        await LinkedFolderIndex.shared.configure(roots)
    }

    func apply(_ update: LinkedFolderIndex.Update) {
        if update.revision >= appliedRevision {
            appliedRevision = update.revision
            if recentFiles != update.recentFiles { recentFiles = update.recentFiles }
        }
        if !update.changedDirectories.isEmpty || update.indexChanged {
            NotificationCenter.default.post(name: .linkedFolderContentsDidChange,
                                            object: update)
        }
        if !update.relocatedRoots.isEmpty {
            // Re-resolve and rebase existing sessions through the same bookmark
            // path used for activation, rather than guessing folder rename pairs.
            Task { await Self.refreshRootLocations() }
        }
    }

    static func refreshRootLocations() async {
        if let task = shared.rootRefreshTask { return await task.value }
        let context = PersistenceController.shared.newTaskContext()
        let task = Task.detached(priority: .utility) {
            await context.perform {
                let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                request.predicate = NSPredicate(format: "parent == nil")
                for folder in (try? context.fetch(request)) ?? [] {
                    _ = try? folder.refreshResolvedLocation(context: context)
                }
            }
        }
        shared.rootRefreshTask = task
        await task.value
        shared.rootRefreshTask = nil
    }

    static func affects(_ notification: Notification, folderURL: URL?) -> Bool {
        guard let folderURL else { return false }
        if let update = notification.object as? LinkedFolderIndex.Update {
            return update.changedDirectories.contains { $0.standardizedFileURL.path == folderURL.standardizedFileURL.path }
                || update.invalidatedSubtrees.contains { LinkedFolderScanner.contains(folderURL, in: $0) }
        }
        return (notification.object as? [URL])?.contains {
            folderURL.standardizedFileURL.path == $0.standardizedFileURL.path
        } == true
    }
}
