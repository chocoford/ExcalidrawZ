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
        let (sourceURL, targetURL) = try await context.perform {
            guard case let folder as LocalFolder = context.object(with: folderID),
                  case let targetFolder as LocalFolder = context.object(with: targetFolderID),
                  let targetURL = targetFolder.url,
                  let sourceURL = folder.url else {
                throw CancellationError()
            }
            return (sourceURL, targetURL)
        }

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

        // find all files in sourceURL to update mappings
        // Collect all files first to avoid Swift 6 async iterator warning
        let allFiles: [URL] = {
            guard let enumerator = FileManager.default.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: []
            ) else {
                return []
            }
            return enumerator.compactMap { $0 as? URL }
        }()

        // Update mappings for all files
        for file in allFiles {
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

        /// Move the folder with coordinated access
        try await FileCoordinator.shared.coordinatedMove(from: sourceURL, to: newURL)

        try await context.perform {
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
    ) async throws -> [URL : URL] {
        guard case let folder as LocalFolder = context.object(with: folderID) else { return [:] }
        return try await folder.withSecurityScopedURL { scopedURL async throws -> [URL : URL] in
            var urlMapping = [URL : URL]()
            let fileManager = FileManager.default

            for file in filesToMove {

                var newURL = scopedURL.appendingPathComponent(
                    file.deletingPathExtension().lastPathComponent,
                    conformingTo: .excalidrawFile
                )
                var i = 1
                while fileManager.fileExists(at: newURL) {
                    newURL = scopedURL.appendingPathComponent(
                        file.deletingPathExtension().lastPathComponent + " (\(i))",
                        conformingTo: .excalidrawFile
                    )
                    i += 1
                }

                try await FileCoordinator.shared.coordinatedMove(from: file, to: newURL)

                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil

                // Also update checkpoints
                self.updateCheckpoints(oldURL: file, newURL: newURL)

                do {
                    try await PersistenceController.shared.aiConversationRepository.rebindConversations(
                        from: AIConversationFileScope(kind: .localFile, id: file.absoluteString),
                        to: AIConversationFileScope(kind: .localFile, id: newURL.absoluteString)
                    )
                    try await PersistenceController.shared.aiConversationRepository.rebindConversations(
                        from: AIConversationFileScope(kind: .temporaryFile, id: file.absoluteString),
                        to: AIConversationFileScope(kind: .localFile, id: newURL.absoluteString)
                    )
                } catch {
                    print("Warning: Failed to rebind AI conversations for moved local file: \(error)")
                }

                urlMapping[file] = newURL
            }

            return urlMapping
        }
    }
}
