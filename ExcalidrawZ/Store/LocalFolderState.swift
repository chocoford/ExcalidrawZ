//
//  LocalFolderState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/27/25.
//

import SwiftUI
import Combine
import CoreData
import Logging

private let localFolderStateLogger = Logger(label: "LocalFolderState")

final class LocalFolderState: ObservableObject {
    var refreshFilesPublisher = PassthroughSubject<Void, Never>()
    var itemRemovedPublisher = PassthroughSubject<String, Never>()
    var itemRenamedPublisher = PassthroughSubject<String, Never>()
    var itemCreatedPublisher = PassthroughSubject<String, Never>()
    var itemUpdatedPublisher = PassthroughSubject<String, Never>()
    var itemsMovedPublisher = PassthroughSubject<[URL: URL], Never>()

    @MainActor
    func publishMovedItems(_ mapping: [URL: URL]) {
        guard !mapping.isEmpty else { return }
        itemsMovedPublisher.send(mapping)
    }

    // MARK: - File Status Management
    
    public func moveLocalFolder(
        _ folderID: NSManagedObjectID,
        to targetFolderID: NSManagedObjectID,
        forceRefreshFiles: Bool,
        context: NSManagedObjectContext
    ) async throws {
        try await LocalFileUtils.moveLocalFolder(
            folderID,
            to: targetFolderID,
            context: context
        )

        if forceRefreshFiles {
            await MainActor.run {
                self.objectWillChange.send()
                self.refreshFilesPublisher.send()
            }
        }

        let localFolderIDs: [NSManagedObjectID] = await context.perform {
            var result: [NSManagedObjectID] = []
            var currentID: NSManagedObjectID? = targetFolderID
            var currentFolder = context.object(with: targetFolderID) as? LocalFolder

            while let folderID = currentID {
                result.insert(folderID, at: 0)
                currentFolder = currentFolder?.parent
                currentID = currentFolder?.objectID
            }
            return result
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

        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: sourceURL) {
            try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: targetURL) {
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

                let fileMappings = allFiles.map { file -> (source: URL, destination: URL) in
                    // get the changed folder
                    let relativePath = file.filePath.suffix(from: sourceURL.filePath.endIndex)
                    let fileNewURL = if #available(macOS 13.0, *) {
                        newURL.appending(path: relativePath)
                    } else {
                        newURL.appendingPathComponent(String(relativePath))
                    }
                    return (file, fileNewURL)
                }

                /// Move the folder with coordinated access
                try await FileCoordinator.shared.coordinatedMove(from: sourceURL, to: newURL)

                // Update dependent state only after the file-system move succeeds.
                for mapping in fileMappings {
                    ExcalidrawFile.localFileURLIDMapping[mapping.destination] =
                        ExcalidrawFile.localFileURLIDMapping[mapping.source]
                    ExcalidrawFile.localFileURLIDMapping[mapping.source] = nil
                    self.updateCheckpoints(
                        oldURL: mapping.source,
                        newURL: mapping.destination
                    )
                }

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
                localFolderStateLogger.error("Failed to update local checkpoints after URL change: \(error)")
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
                if file.deletingLastPathComponent().standardizedFileURL
                    == scopedURL.standardizedFileURL {
                    urlMapping[file] = file
                    continue
                }

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

                try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: file) {
                    try await FileCoordinator.shared.coordinatedMove(from: file, to: newURL)
                }

                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil

                // Also update checkpoints
                self.updateCheckpoints(oldURL: file, newURL: newURL)

                do {
                    let oldLocalScope = AIConversationFileScope(kind: .localFile, id: file.absoluteString)
                    let oldTemporaryScope = AIConversationFileScope(kind: .temporaryFile, id: file.absoluteString)
                    let newLocalScope = AIConversationFileScope(kind: .localFile, id: newURL.absoluteString)
                    try await PersistenceController.shared.aiConversationRepository.rebindConversations(
                        from: oldLocalScope,
                        to: newLocalScope
                    )
                    await AIChatPreferences.shared.rebindFileAccessOverride(
                        from: oldLocalScope,
                        to: newLocalScope
                    )
                    try await PersistenceController.shared.aiConversationRepository.rebindConversations(
                        from: oldTemporaryScope,
                        to: newLocalScope
                    )
                    await AIChatPreferences.shared.rebindFileAccessOverride(
                        from: oldTemporaryScope,
                        to: newLocalScope
                    )
                } catch {
                    localFolderStateLogger.warning("Failed to rebind AI conversations for moved local file: \(error)")
                }

                urlMapping[file] = newURL
            }

            return urlMapping
        }
    }
}
