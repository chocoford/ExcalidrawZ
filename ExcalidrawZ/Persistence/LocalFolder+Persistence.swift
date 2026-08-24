//
//  LocalFolder+Persisitence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/25/25.
//

import Foundation
import CoreData
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let localFolderResolvedLocationDidChange = Notification.Name("localFolderResolvedLocationDidChange")
}

enum LocalFolderLocationChangeUserInfoKey {
    static let oldURL = "oldURL"
    static let newURL = "newURL"
}

extension LocalFolder {

    struct ResolvedLocationChange: Sendable {
        let oldURL: URL
        let newURL: URL
    }

#if os(macOS)
    var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        [.withSecurityScope]
    }
    var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        [.withSecurityScope]
    }
#elseif os(iOS)
    // iOS document-picker bookmarks implicitly start their ephemeral security
    // scope when resolved. The matching stop happens after each operation.
    var bookmarkResolutionOptions: URL.BookmarkResolutionOptions { [] }
    var bookmarkCreationOptions: URL.BookmarkCreationOptions { [] }
#endif
    
    var scopedURL: URL? {
        get throws {
            try resolvedBookmark()?.url
        }
    }

    private func resolvedBookmark() throws -> (url: URL, isStale: Bool)? {
        guard let bookmarkData else { return nil }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            bookmarkDataIsStale: &isStale
        )
        return (url.standardizedFileURL, isStale)
    }
    
    public convenience init(url: URL, context: NSManagedObjectContext) throws {
        self.init(context: context)
        self.url = url
        self.filePath = url.filePath
        self.importedAt = Date()
        self.bookmarkData = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: [.nameKey],
            relativeTo: nil
        )
    }
    
    public override func willSave() {
        super.willSave()
        setPrimitiveValue(url?.filePath, forKey: #keyPath(LocalFolder.filePath))
    }

    /// Reconciles the persisted folder tree with the URL currently resolved by
    /// the top-level security-scoped bookmark. Bookmarks can continue resolving
    /// after a folder is renamed or moved, while the Core Data URL remains a
    /// snapshot of the location that was originally linked.
    @discardableResult
    func refreshResolvedLocation(context: NSManagedObjectContext) throws -> ResolvedLocationChange? {
        guard parent == nil, let resolved = try resolvedBookmark() else { return nil }

        try Self.beginResolvedBookmarkAccess(to: resolved.url)
        defer { resolved.url.stopAccessingSecurityScopedResource() }

        let oldURL = (url ?? filePath.map { URL(fileURLWithPath: $0) })?.standardizedFileURL
        let locationChanged = oldURL != resolved.url
        guard locationChanged || resolved.isStale else { return nil }

        let change = try context.performAndWait { () throws -> ResolvedLocationChange? in
            let previousURL = (self.url ?? self.filePath.map { URL(fileURLWithPath: $0) })?
                .standardizedFileURL

            if let previousURL, previousURL != resolved.url {
                try self.rebasePersistedURLs(
                    from: previousURL,
                    to: resolved.url,
                    context: context
                )
            } else {
                self.url = resolved.url
                self.filePath = resolved.url.filePath
            }

            self.bookmarkData = try resolved.url.bookmarkData(
                options: self.bookmarkCreationOptions,
                includingResourceValuesForKeys: [.nameKey],
                relativeTo: nil
            )

            if context.hasChanges {
                try context.save()
            }

            guard let previousURL, previousURL != resolved.url else { return nil }
            return ResolvedLocationChange(oldURL: previousURL, newURL: resolved.url)
        }

        if let change {
            let folderID = objectID
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .localFolderResolvedLocationDidChange,
                    object: folderID,
                    userInfo: [
                        LocalFolderLocationChangeUserInfoKey.oldURL: change.oldURL,
                        LocalFolderLocationChangeUserInfoKey.newURL: change.newURL,
                    ]
                )
            }
        }
        return change
    }

    private func rebasePersistedURLs(
        from oldRootURL: URL,
        to newRootURL: URL,
        context: NSManagedObjectContext
    ) throws {
        func updateFolder(_ folder: LocalFolder) {
            if let sourceURL = folder.url ?? folder.filePath.map({ URL(fileURLWithPath: $0) }),
               let destinationURL = sourceURL.rebased(from: oldRootURL, to: newRootURL) {
                folder.url = destinationURL
                folder.filePath = destinationURL.filePath
            }
            for case let child as LocalFolder in folder.children?.allObjects ?? [] {
                updateFolder(child)
            }
        }
        updateFolder(self)

        let checkpointRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
        for checkpoint in try context.fetch(checkpointRequest) {
            if let sourceURL = checkpoint.url,
               let destinationURL = sourceURL.rebased(from: oldRootURL, to: newRootURL) {
                checkpoint.url = destinationURL
            }
        }

        let existingMappings = ExcalidrawFile.localFileURLIDMapping
        for (sourceURL, fileID) in existingMappings {
            guard let destinationURL = sourceURL.rebased(from: oldRootURL, to: newRootURL) else { continue }
            ExcalidrawFile.localFileURLIDMapping[sourceURL] = nil
            ExcalidrawFile.localFileURLIDMapping[destinationURL] = fileID
        }
    }
    
    private struct InvalidScopedURLError: Error {}
    private struct StartAccessingSecurityScopedResourceError: LocalizedError {
        var errorDescription: String? { "Start accessing security scoped resource failed." }
    }

    private static func beginSecurityScopedAccess(to url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
    }

    private static func beginResolvedBookmarkAccess(to url: URL) throws {
#if os(macOS)
        try beginSecurityScopedAccess(to: url)
#elseif os(iOS)
        // Resolving the document-picker bookmark starts access implicitly.
        // Calling startAccessing again can return false even though the URL is
        // accessible, so the resolved scope is balanced only by stop below.
#endif
    }

    private static func isPendingUbiquitousDownload(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        return values?.isUbiquitousItem == true
            && values?.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Returns nil while a File Provider-backed directory is still being
    /// materialized. Callers must preserve their current UI or Core Data tree
    /// instead of interpreting that state as an empty directory.
    static func materializedDirectoryContents(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL]? {
#if os(iOS)
        if isPendingUbiquitousDownload(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }
#endif

        var contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        )

#if os(iOS)
        // Some File Provider implementations transiently return an empty first
        // enumeration immediately after a bookmark is restored.
        if contents.isEmpty {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options
            )
            if contents.isEmpty, isPendingUbiquitousDownload(url) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                return nil
            }
        }
#endif
        return contents
    }

    private var securityScopeRoot: LocalFolder {
        var folder = self
        while let parent = folder.parent {
            folder = parent
        }
        return folder
    }

    private func resolvedAccessURLs() throws -> (target: URL, scope: URL) {
        let root = securityScopeRoot
        guard let scopeURL = try root.scopedURL else {
            throw InvalidScopedURLError()
        }

        let targetURL: URL
        if objectID == root.objectID {
            targetURL = scopeURL
        } else if let url {
            targetURL = url
        } else if let filePath {
            targetURL = URL(fileURLWithPath: filePath)
        } else {
            throw InvalidScopedURLError()
        }
        return (targetURL, scopeURL)
    }

    @discardableResult
    public func withSecurityScopedURL<T>(actions: (_ scopedURL: URL) throws -> T) throws -> T {
        let urls = try resolvedAccessURLs()
        try Self.beginResolvedBookmarkAccess(to: urls.scope)
        defer { urls.scope.stopAccessingSecurityScopedResource() }

        return try actions(urls.target)
    }

    @discardableResult
    public func withSecurityScopedURL<T>(actions: @escaping (_ scopedURL: URL) async throws -> T) async throws -> T {
        let urls = try resolvedAccessURLs()
        try Self.beginResolvedBookmarkAccess(to: urls.scope)
        defer { urls.scope.stopAccessingSecurityScopedResource() }
        return try await actions(urls.target)
    }

    static func withSecurityScopedAccessToContainingFolder<T>(
        for fileURL: URL,
        action: () async throws -> T
    ) async throws -> T {
        guard let bookmarkData = try await securityScopedBookmarkData(forLocalFileAt: fileURL) else {
            return try await action()
        }

        do {
            return try await withSecurityScopedBookmark(bookmarkData, action: action)
        } catch is StartAccessingSecurityScopedResourceError {
            // A direct Files open can provide a valid file-scoped grant even
            // when the saved containing-folder bookmark is unavailable.
            return try await action()
        }
    }

    static func modificationDate(forLocalFileAt fileURL: URL) async throws -> Date? {
        try await withSecurityScopedAccessToContainingFolder(for: fileURL) {
            try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        }
    }

    static func rootFolder(
        containing url: URL,
        in context: NSManagedObjectContext
    ) throws -> LocalFolder? {
        let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        request.predicate = NSPredicate(format: "parent == nil")

        return try context.fetch(request)
            .compactMap { folder -> (folder: LocalFolder, rootURL: URL)? in
                guard let folderPath = folder.filePath else { return nil }
                let rootURL = URL(fileURLWithPath: folderPath, isDirectory: true)
                    .standardizedFileURL
                guard url.isContained(in: rootURL) else { return nil }
                return (folder, rootURL)
            }
            .max { $0.rootURL.path.count < $1.rootURL.path.count }?
            .folder
    }

    private static func securityScopedBookmarkData(forLocalFileAt fileURL: URL) async throws -> Data? {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            // The picker grant belongs to a top-level linked folder and already
            // covers its descendants. Child bookmarks are navigation metadata;
            // using the root avoids provider-specific descendant bookmark behavior.
            return try rootFolder(containing: fileURL, in: context)?.bookmarkData
        }
    }

    private static func withSecurityScopedBookmark<T>(
        _ bookmarkData: Data,
        action: () async throws -> T
    ) async throws -> T {
        var isStale = false
#if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
        let options: URL.BookmarkResolutionOptions = []
#endif
        let scopedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: options,
            bookmarkDataIsStale: &isStale
        )

        try beginResolvedBookmarkAccess(to: scopedURL)
        defer { scopedURL.stopAccessingSecurityScopedResource() }

        return try await action()
    }

    private static func localFolder(
        for url: URL,
        parent: LocalFolder,
        context: NSManagedObjectContext
    ) throws -> LocalFolder {
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        fetchRequest.predicate = NSPredicate(format: "filePath == %@", url.filePath)
        fetchRequest.fetchLimit = 1

        if let existingFolder = try context.fetch(fetchRequest).first {
            existingFolder.parent = parent
            return existingFolder
        }

        let child = try LocalFolder(url: url, context: context)
        child.parent = parent
        return child
    }
    
    func refreshChildren(
        context: NSManagedObjectContext,
        recursively: Bool = true
    ) throws {
        try refreshResolvedLocation(context: context)
        try self.withSecurityScopedURL { url in
            guard let contents = try Self.materializedDirectoryContents(
                at: url,
                includingPropertiesForKeys: [.nameKey, .isHiddenKey]
            ) else { return }
            try context.performAndWait {
                let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                fetchRequest.predicate = NSPredicate(format: "parent = %@", self)
                let childeren = try context.fetch(fetchRequest)
                /// Children folders that should be deleted
                var missingChidren = childeren
                for url in contents.filter({
                    $0.isDirectory && (try? $0.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == false
                }) {
                    /// If found, remove from `missingChidren`
                    if let index = missingChidren.firstIndex(where: {$0.url == url}) {
                        missingChidren.remove(at: index)
                    }
                    
                    /// If self.children already contains this folder, skip
                    if self.children?.contains(where: {
                        if let child = $0 as? LocalFolder {
                            return child.url == url
                        }
                        return false
                    }) == true {
                        continue
                    }
                    /// Otherwise, create/reuse a LocalFolder instance and add it to children
                    let child = try Self.localFolder(for: url, parent: self, context: context)
                    self.addToChildren(child)
                }
                
                /// remove missing children folders
                for folder in missingChidren {
                    // also delete all children of this folder
                    try deleteLocalFolder(folder, context: context)
                }
                
                if recursively {
                    for case let subfolder as LocalFolder in self.children?.allObjects ?? [] {
                        try subfolder.refreshChildren(context: context)
                    }
                }
                
                try context.save()
            }
        }
    }
    
    func getFiles<T>(
        deep: Bool,
        properties: [URLResourceKey]? = nil,
        action: (_ fileURL: URL) throws -> T = { $0 }
    ) throws -> [T] {
        try self.withSecurityScopedURL { scopedURL in
            let filemanager = FileManager.default
            if deep {
                guard let enumerator = filemanager.enumerator(at: scopedURL, includingPropertiesForKeys: properties) else {
                    return []
                }
                var results: [T] = []
                for case let file as URL in enumerator {
                    if file.pathExtension == "excalidraw" {
                        try results.append(action(file))
                    }
                }
                return results
            } else {
                let urls = try filemanager.contentsOfDirectory(at: scopedURL, includingPropertiesForKeys: properties)
                return try urls.filter({
                    $0.pathExtension == "excalidraw"
                }).map {
                    try action($0)
                }
            }
        }
    }
    
    func getFolders() throws -> [URL] {
        try self.withSecurityScopedURL { scopedURL in
            let filemanager = FileManager.default
            let urls = try filemanager.contentsOfDirectory(
                at: scopedURL,
                includingPropertiesForKeys: []
            )
            return urls.filter({ $0.isDirectory })
        }
    }

    /// Check if folder path exists and is accessible
    /// - Returns: Result with success or error with localized description
    func checkPathExists() -> Result<Void, LocalFolderPathError> {
        do {
            return try withSecurityScopedURL { url in
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: url.filePath,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue {
                    return .success(())
                }
                return .failure(
                    LocalFolderPathError(
                        message: "The folder \"\(url.lastPathComponent)\" could not be found. It may have been moved or deleted.\n\nPath: \(url.filePath)"
                    )
                )
            }
        } catch {
            return .failure(
                LocalFolderPathError(
                    message: error.localizedDescription
                )
            )
        }
    }
}

/// Error type for LocalFolder path validation
struct LocalFolderPathError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }

//    func moveUnder(destination url: URL) throws {
//        guard let sourceURL = self.url,
//              let enumerator = FileManager.default.enumerator(
//                at: sourceURL,
//                includingPropertiesForKeys: [.isDirectoryKey]
//              ) else {
//            return
//        }
//        
//        try withSecurityScopedURL { scopedURL in
//            let fileCoordinator = NSFileCoordinator()
//            let filemanager = FileManager.default
//            
//            var destinationURL = url.appendingPathComponent(
//                self.name ?? scopedURL.lastPathComponent,
//                conformingTo: .directory
//            )
//            
//            var i = 1
//            while filemanager.fileExists(atPath: destinationURL.filePath) {
//                destinationURL = url.appendingPathComponent(
//                    self.name ?? scopedURL.lastPathComponent + " (\(i))",
//                    conformingTo: .directory
//                )
//            }
//            // Move
//            fileCoordinator.coordinate(
//                writingItemAt: scopedURL,
//                options: .forMoving,
//                writingItemAt: destinationURL,
//                options: .forReplacing,
//                error: nil
//            ) { src, dist in
//                try? FileManager.default.moveItem(
//                    at: src,
//                    to: dist
//                )
//            }
//        }
//    }
}


func deleteLocalFolder(
    _ folder: LocalFolder,
    withChildren: Bool = true,
    context: NSManagedObjectContext
) throws {
    try context.performAndWait {
        let children: [LocalFolder] = folder.children?.allObjects.compactMap { $0 as? LocalFolder } ?? []
        if withChildren {
            for child in children {
                try deleteLocalFolder(child, withChildren: true, context: context)
            }
        }
        
        context.delete(folder)
        
        try context.save()
    }
}
