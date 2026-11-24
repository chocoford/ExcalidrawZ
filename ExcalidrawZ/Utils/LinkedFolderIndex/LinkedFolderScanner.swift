import Foundation

/// Disk work shared by the index and directory browsers. Never runs on the UI context.
enum LinkedFolderScanner {
    struct Entry: Codable, Equatable, Sendable {
        let url: URL
        let modifiedAt: Date
        var updatedAt: Date? = nil
        var createdAt: Date? = nil
    }

    struct Result: Sendable {
        var files: [Entry] = []
        var unreadableDirectories: [URL] = []
    }

    static func isDrawing(_ url: URL) -> Bool {
        url.pathExtension == "excalidraw"
            || (["png", "svg"].contains(url.pathExtension)
                && url.deletingPathExtension().pathExtension == "excalidraw")
    }

    static func contains(_ child: URL, in parent: URL) -> Bool {
        let path = child.standardizedFileURL.path
        let root = parent.standardizedFileURL.path
        return path == root || path.hasPrefix(root == "/" ? root : root + "/")
    }

    static func visible(_ url: URL, under root: URL) -> Bool {
        guard contains(url, in: root) else { return false }
        let relative = url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Remove overlapping scan scopes; an explicitly linked hidden folder remains a root.
    static func minimalRoots(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in Set(urls.map(\.standardizedFileURL)).sorted(by: { $0.path.count < $1.path.count }) {
            if !result.contains(where: { visible(url, under: $0) }) { result.append(url) }
        }
        return result
    }

    static func entry(at url: URL) throws -> Entry? {
        guard isDrawing(url) else { return nil }
        var freshURL = URL(fileURLWithPath: url.path)
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [
            .isDirectoryKey, .contentModificationDateKey, .creationDateKey,
        ])
        guard values.isDirectory != true else { return nil }
        return Entry(url: freshURL.standardizedFileURL, modifiedAt: max(
            values.contentModificationDate ?? .distantPast,
            values.creationDate ?? .distantPast
        ), updatedAt: values.contentModificationDate, createdAt: values.creationDate)
    }

    static func immediateDirectories(at url: URL, retryIfEmpty: Bool = true,
                                     isCancelled: () -> Bool = { Task.isCancelled }) throws -> [URL] {
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in failure = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var directories: [URL] = []
        var inspected = 0
        while let child = enumerator.nextObject() as? URL {
            inspected += 1
            if isCancelled() { throw CancellationError() }
            try autoreleasepool {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true, values.isSymbolicLink != true { directories.append(child) }
            }
        }
        if let failure { throw failure }
#if os(iOS)
        if inspected == 0, retryIfEmpty {
            return try immediateDirectories(at: url, retryIfEmpty: false, isCancelled: isCancelled)
        }
#endif
        return directories
    }

    static func immediateItemCount(at url: URL, isCancelled: () -> Bool = { Task.isCancelled }) throws -> Int {
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in failure = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var count = 0
        while let child = enumerator.nextObject() as? URL {
            if isCancelled() { throw CancellationError() }
            try autoreleasepool {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink != true, values.isDirectory == true || isDrawing(child) { count += 1 }
            }
        }
        if let failure { throw failure }
        return count
    }

    static func scan(_ url: URL, recursively: Bool = true,
                     retryIfEmpty: Bool = true,
                     onBatch: (([Entry]) -> Void)? = nil,
                     isCancelled: () -> Bool = { Task.isCancelled }) throws -> Result {
        if isCancelled() { throw CancellationError() }
#if os(iOS)
        let providerValues = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if providerValues?.isUbiquitousItem == true, providerValues?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw CocoaError(.fileReadUnknown)
        }
#endif
        // URL resource values may cache the old type after a move/deletion.
        // A fresh stat of the path is necessary before reconciling that scope.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink { return Result() }
        if attributes[.type] as? FileAttributeType != .typeDirectory {
            return Result(files: try entry(at: url).map { [$0] } ?? [])
        }
        var result = Result()
        var batch: [Entry] = []
        var inspected = 0
        var lastBatchAt = Date()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: recursively ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { failedURL, _ in
                result.unreadableDirectories.append(failedURL)
                return true
            }
        ) else { throw CocoaError(.fileReadUnknown) }

        while let file = enumerator.nextObject() as? URL {
            if isCancelled() { throw CancellationError() }
            inspected += 1
            if onBatch != nil, inspected % 256 == 0, Date().timeIntervalSince(lastBatchAt) >= 0.5, !batch.isEmpty {
                onBatch?(batch)
                batch.removeAll(keepingCapacity: true)
                lastBatchAt = Date()
            }
            autoreleasepool {
                let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    // DirectoryEnumerator already does not follow symlinks.
                    // skipDescendants() here would skip the *next* directory.
                    return
                } else if isDrawing(file) {
                    do {
                        if let entry = try entry(at: file) {
                            result.files.append(entry)
                            if onBatch != nil, batch.count < 128 { batch.append(entry) }
                        }
                    } catch {
                        // A transient permission/provider error must not erase a cached entry.
                        result.unreadableDirectories.append(file)
                    }
                }
            }
        }
#if os(iOS)
        if inspected == 0, result.unreadableDirectories.isEmpty, retryIfEmpty {
            return try scan(url, recursively: recursively, retryIfEmpty: false, onBatch: onBatch, isCancelled: isCancelled)
        }
#endif
        return result
    }
}

/// Core Data's perform closures do not inherit the calling Swift task's cancellation.
final class LinkedFolderScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Holds a picker grant until every cancelled worker has actually exited.
final class LinkedFolderAccess: @unchecked Sendable {
    let url: URL
    private let releasesScope: Bool

    init(url: URL, bookmark: Data?) throws {
        guard let bookmark else {
            self.url = url.standardizedFileURL
            releasesScope = false
            return
        }
        var stale = false
#if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
        let options: URL.BookmarkResolutionOptions = []
#endif
        self.url = try URL(resolvingBookmarkData: bookmark, options: options,
                           bookmarkDataIsStale: &stale).standardizedFileURL
#if os(macOS)
        guard self.url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
#endif
        releasesScope = true
    }

    deinit {
        if releasesScope { url.stopAccessingSecurityScopedResource() }
    }
}
