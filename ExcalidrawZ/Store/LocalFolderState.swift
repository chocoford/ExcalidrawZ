//
//  LocalFolderState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/27/25.
//

import SwiftUI
import Combine
import CoreData

final class LocalFolderState: ObservableObject {
    var refreshFilesPublisher = PassthroughSubject<Void, Never>()
    var itemRemovedPublisher = PassthroughSubject<String, Never>()
    var itemRenamedPublisher = PassthroughSubject<String, Never>()
    var itemCreatedPublisher = PassthroughSubject<String, Never>()
    var itemUpdatedPublisher = PassthroughSubject<String, Never>()

    // MARK: - File Status Management

    /// Get status box for a local file
    /// - Parameter url: The file URL
    /// - Returns: FileStatusBox for observing file status
    @MainActor
    func statusBox(for url: URL) -> FileStatusBox {
        return FileSyncCoordinator.shared.statusBox(for: url)
    }
    
    public func moveLocalFolder(
        _ folderID: NSManagedObjectID,
        to targetFolderID: NSManagedObjectID,
        forceRefreshFiles: Bool,
        context: NSManagedObjectContext
    ) throws {
        Task {
            do {
                try await LocalFileUtils.moveLocalFolder(
                    folderID,
                    to: targetFolderID,
                    context: context
                )
                
                // Toggle refresh state
                if forceRefreshFiles {
                    Task {
                        await MainActor.run {
                            self.objectWillChange.send()
                            self.refreshFilesPublisher.send()
                        }
                    }
                }
                let targetFolder = context.object(with: targetFolderID) as? LocalFolder
                // auto expand
                var localFolderIDs: [NSManagedObjectID] = []
                do {
                    var targetFolderID: NSManagedObjectID? = targetFolderID
                    var parentFolder: LocalFolder? = targetFolder
                    while true {
                        if let targetFolderID {
                            localFolderIDs.insert(targetFolderID, at: 0)
                        }
                        guard let parentFolderID = parentFolder?.parent?.objectID else {
                            break
                        }
                        parentFolder = context.object(with: parentFolderID) as? LocalFolder
                        targetFolderID = parentFolder?.objectID
                    }
                }
                for localFolderID in localFolderIDs {
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .shouldExpandGroup,
                            object: localFolderID
                        )
                    }
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                }
            } catch {
                print(error)
            }
        }
    }
}

class LocalFileUtils {
    public static func moveLocalFolder(
        _ folderID: NSManagedObjectID,
        to targetFolderID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            guard case let folder as LocalFolder = context.object(with: folderID),
                  case let targetFolder as LocalFolder = context.object(with: targetFolderID),
                  let targetURL = targetFolder.url,
                  let sourceURL = folder.url else { return }
            
            /// Get the final target folder URL
            var newURL: URL = targetURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                conformingTo: .directory
            )
            
            if newURL == sourceURL { return }
            
            var candidateIndex = 1
            while FileManager.default.fileExists(at: newURL) {
                newURL = targetURL.appendingPathComponent(
                    sourceURL.lastPathComponent + "_\(candidateIndex)",
                    conformingTo: .directory
                )
                candidateIndex += 1
            }
            
            
            try folder.withSecurityScopedURL { sourceURL in
                try targetFolder.withSecurityScopedURL { taretURL in
                    
                    // find all files in sourceURL...
                    guard let enumerator = FileManager.default.enumerator(
                        at: sourceURL,
                        includingPropertiesForKeys: []
                    ) else {
                        return
                    }
                    
                    for case let file as URL in enumerator {
                        // get the changed folder
                        let relativePath = file.filePath.suffix(from: sourceURL.filePath.endIndex)
                        let fileNewURL = if #available(macOS 13.0, *) {
                            newURL.appending(path: relativePath)
                        } else {
                            newURL.appendingPathComponent(String(relativePath))
                        }
                        
                        // Update local file ID mapping
                        ExcalidrawFile.localFileURLIDMapping[fileNewURL] = ExcalidrawFile.localFileURLIDMapping[file]
                        ExcalidrawFile.localFileURLIDMapping[file] = nil
                        
                        // Also update checkpoints in background
                        self.updateCheckpoints(oldURL: file, newURL: fileNewURL)
                    }
                    
                    /// update the folder URL
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(writingItemAt: taretURL, options: .forMoving, error: nil) { url in
                        do {
                            try FileManager.default.moveItem(
                                at: sourceURL,
                                to: newURL
                            )
                        } catch {
                            print(error)
                        }
                    }
                    
                    // update LocalFolder
                    guard case let folder as LocalFolder = context.object(with: folderID),
                          let targetFolder = context.object(with: targetFolderID) as? LocalFolder else {
                        return
                    }
                    folder.url = newURL
                    folder.filePath = newURL.filePath
#if os(macOS)
                    let options: URL.BookmarkCreationOptions = [.withSecurityScope]
#elseif os(iOS)
                    let options: URL.BookmarkCreationOptions = []
#endif
                    folder.bookmarkData = try newURL.bookmarkData(
                        options: options,
                        includingResourceValuesForKeys: [.nameKey]
                    )
                    folder.parent = targetFolder
                    try context.save()
                }
            }
        }
    }
    
    static func updateCheckpoints(oldURL: URL, newURL: URL) {
        Task.detached {
            let context = PersistenceController.shared.container.newBackgroundContext()
            do {
                try await context.perform {
                    let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
                    fetchRequest.predicate = NSPredicate(format: "url = %@", oldURL as NSURL)
                    let checkpoints = try context.fetch(fetchRequest)
                    checkpoints.forEach { $0.url = newURL }
                    try context.save()
                }
            } catch {
                print(error)
            }
        }
    }
    
    public static func moveLocalFiles(
        _ filesToMove: [URL],
        to folderID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) throws -> [URL : URL] {
        guard case let folder as LocalFolder = context.object(with: folderID) else { return [:] }
        return try folder.withSecurityScopedURL { scopedURL in
            var urlMapping = [URL : URL]()

            let fileCoordinator = NSFileCoordinator()
            fileCoordinator.coordinate(
                writingItemAt: scopedURL,
                options: .forMoving,
                error: nil
            ) { url in
                let fileManager = FileManager.default
                do {
                    for file in filesToMove {
                        
                        var newURL = url.appendingPathComponent(
                            file.deletingPathExtension().lastPathComponent,
                            conformingTo: .excalidrawFile
                        )
                        var i = 1
                        while fileManager.fileExists(at: newURL) {
                            newURL = url.appendingPathComponent(
                                file.deletingPathExtension().lastPathComponent + " (\(i))",
                                conformingTo: .excalidrawFile
                            )
                            i += 1
                        }
                        
                        try fileManager.moveItem(
                            at: file,
                            to: newURL
                        )
                        
                        // Update local file ID mapping
                        ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                        ExcalidrawFile.localFileURLIDMapping[file] = nil
                        
                        // Also update checkpoints
                        self.updateCheckpoints(oldURL: file, newURL: newURL)
                        
                        urlMapping[file] = newURL
                    }
                } catch {
                    print(error)
                }
            }
            return urlMapping
        }
    }
}
