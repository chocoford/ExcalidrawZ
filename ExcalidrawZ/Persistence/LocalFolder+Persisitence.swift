//
//  LocalFolder+Persisitence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/25/25.
//

import Foundation
import CoreData

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
            throw InvalidScopedURLError()
        }
        guard scopedURL.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
        Task {
            defer { scopedURL.stopAccessingSecurityScopedResource() }
            await actions(scopedURL)
        }
    }
    @discardableResult
    public func withSecurityScopedURL<T>(actions: @escaping (_ scopedURL: URL) async throws -> T) async throws -> T {
        guard let scopedURL = try self.scopedURL else {
            throw InvalidScopedURLError()
        }
        guard scopedURL.startAccessingSecurityScopedResource() else {
            throw StartAccessingSecurityScopedResourceError()
        }
        defer { scopedURL.stopAccessingSecurityScopedResource() }
        return try await actions(scopedURL)
    }
    
    func refreshChildren(context: NSManagedObjectContext) throws {
        try self.withSecurityScopedURL { url in
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.nameKey]
            )
            try context.performAndWait {
                let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                fetchRequest.predicate = NSPredicate(format: "parent = %@", self)
                let childeren = try context.fetch(fetchRequest)
                var mismatchedFolders = childeren
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
                }
                
                // remove mismatched folders
                for folder in mismatchedFolders {
                    context.delete(folder)
                }
                
                for case let subfolder as LocalFolder in self.children?.allObjects ?? [] {
                    try subfolder.refreshChildren(context: context)
                }
                
                try context.save()
            }
        }
    }
}
