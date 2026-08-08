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

extension LocalFolder {

#if os(macOS)
    var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        [.withSecurityScope]
    }
    var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        [.withSecurityScope]
    }
#elseif os(iOS)
    var bookmarkResolutionOptions: URL.BookmarkResolutionOptions { [] }
    var bookmarkCreationOptions: URL.BookmarkCreationOptions { [] }
#endif
    
    var scopedURL: URL? {
        get throws {
            guard let bookmarkData else { return nil }
            var isStale: Bool = false
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkResolutionOptions,
                bookmarkDataIsStale: &isStale
            )
        }
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
    
    private struct InvalidScopedURLError: Error {}
    private struct StartAccessingSecurityScopedResourceError: LocalizedError {
        var errorDescription: String? { "Start accessing security scoped resource failed." }
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
        guard urls.scope.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
        defer { urls.scope.stopAccessingSecurityScopedResource() }

        return try actions(urls.target)
    }

    @discardableResult
    public func withSecurityScopedURL<T>(actions: @escaping (_ scopedURL: URL) async throws -> T) async throws -> T {
        let urls = try resolvedAccessURLs()
        guard urls.scope.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
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

        return try await withSecurityScopedBookmark(bookmarkData, action: action)
    }

    static func modificationDate(forLocalFileAt fileURL: URL) async throws -> Date? {
        try await withSecurityScopedAccessToContainingFolder(for: fileURL) {
            try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        }
    }

    private static func securityScopedBookmarkData(forLocalFileAt fileURL: URL) async throws -> Data? {
        let filePath = fileURL.standardizedFileURL.path
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            // The picker grant belongs to a top-level linked folder and already
            // covers its descendants. Child bookmarks are navigation metadata;
            // using the root avoids provider-specific descendant bookmark behavior.
            request.predicate = NSPredicate(format: "parent == nil")
            let folders = try context.fetch(request)

            return folders.compactMap { folder -> (path: String, bookmarkData: Data)? in
                guard let folderPath = folder.filePath,
                      let bookmarkData = folder.bookmarkData else {
                    return nil
                }

                let standardizedFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.path
                guard Self.filePath(filePath, isContainedInFolderPath: standardizedFolderPath) else {
                    return nil
                }

                return (standardizedFolderPath, bookmarkData)
            }
            .max { $0.path.count < $1.path.count }?
            .bookmarkData
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

        guard scopedURL.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
        defer { scopedURL.stopAccessingSecurityScopedResource() }

        return try await action()
    }

    private static func filePath(_ filePath: String, isContainedInFolderPath folderPath: String) -> Bool {
        filePath == folderPath || filePath.hasPrefix(folderPath + "/")
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
    
    func refreshChildren(context: NSManagedObjectContext) throws {
        try self.withSecurityScopedURL { url in
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.nameKey, .isHiddenKey]
            )
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
                
                for case let subfolder as LocalFolder in self.children?.allObjects ?? [] {
                    try subfolder.refreshChildren(context: context)
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
