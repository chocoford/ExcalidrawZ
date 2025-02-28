//
//  LocalFolder+Persisitence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/25/25.
//

import Foundation
import CoreData

extension LocalFolder {
    var scopedURL: URL? {
        get throws {
            guard let bookmarkData else { return nil }
            var isStale: Bool = false
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
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
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.nameKey],
            relativeTo: nil
        )
        try self.refreshChildren(context: context)
    }
    
    public override func willSave() {
        super.willSave()
        setPrimitiveValue(url?.filePath, forKey: #keyPath(LocalFolder.filePath))
    }
    
    private struct InvalidScopedURLError: Error {}
    private struct StartAccessingSecurityScopedResourceError: LocalizedError {
        var errorDescription: String? { "Start accessing security scoped resource failed." }
    }
    @discardableResult
    public func withSecurityScopedURL<T>(actions: (_ scopedURL: URL) throws -> T) throws -> T {
        guard let scopedURL = try self.scopedURL else {
            throw InvalidScopedURLError()
        }
        guard scopedURL.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
        defer { scopedURL.stopAccessingSecurityScopedResource() }
        
        return try actions(scopedURL)
    }
    
    public func withSecurityScopedURL(actions: @escaping (_ scopedURL: URL) async -> Void) throws {
        guard let scopedURL = try self.scopedURL else {
            struct InvalidScopedURLError: Error {}
            throw InvalidScopedURLError()
        }
        guard scopedURL.startAccessingSecurityScopedResource() else {
            struct StartAccessingSecurityScopedResourceError: LocalizedError {
                var errorDescription: String? { "Start accessing security scoped resource failed." }
            }
            throw StartAccessingSecurityScopedResourceError()
        }
        Task {
            defer { scopedURL.stopAccessingSecurityScopedResource() }
            await actions(scopedURL)
        }
    }
    
    func refreshChildren(context: NSManagedObjectContext) throws {
        guard let bookmarkData else { return }
        var isStale: Bool = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        guard url.startAccessingSecurityScopedResource() else {
            struct StartAccessingSecurityScopedResourceError: Error {}
            throw StartAccessingSecurityScopedResourceError()
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.nameKey],
            options: [
                .skipsHiddenFiles,
                .skipsSubdirectoryDescendants
            ]
        )
        
        try context.performAndWait {
            var mismatchedFolders = self.children?.allObjects.compactMap {
                ($0 as? LocalFolder)
            } ?? []
            for url in contents.filter({$0.isDirectory}) {
                mismatchedFolders.removeAll(where: {$0.url == url})
                if self.children?.contains(where: {
                    if let child = $0 as? LocalFolder {
                        return child.url == url
                    }
                    return false
                }) == true {
                    continue
                }
                let child = try LocalFolder(url: url, context: context)
                self.addToChildren(child)
                debugPrint("[LocalFolder] new child folder: \(String(describing: child.url))")
            }

            // remove mismatched folders
            for folder in mismatchedFolders {
                context.delete(folder)
                debugPrint("[LocalFolder] remove child folder: \(String(describing: folder.url))")
            }
        }
        
        url.stopAccessingSecurityScopedResource()
    }
}
