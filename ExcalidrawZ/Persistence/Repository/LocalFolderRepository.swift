//
//  LocalFolderRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/24.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for LocalFolder entity operations
actor LocalFolderRepository {
    private let logger = Logger(label: "LocalFolderRepository")

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Import LocalFolder to Group

    /// Import a local folder as a Group
    /// - Parameters:
    ///   - localFolderObjectID: The NSManagedObjectID of the local folder
    ///   - delete: Whether to delete the folder after import
    ///   - parentGroupObjectID: Optional parent group objectID
    /// - Returns: The objectID of the created group
    func importToGroup(
        localFolderObjectID: NSManagedObjectID,
        delete: Bool,
        parentGroupObjectID: NSManagedObjectID? = nil
    ) async throws -> NSManagedObjectID {
        // Get folder URL and children
        let (folderURL, folderName, childrenObjectIDs) = try await context.perform {
            guard let folder = self.context.object(with: localFolderObjectID) as? LocalFolder,
                  let folderURL = folder.url else {
                throw AppError.fileError(.notFound)
            }

            let children = (folder.children ?? []).compactMap { $0 as? LocalFolder }
            return (
                folderURL,
                folderURL.lastPathComponent,
                children.map { $0.objectID }
            )
        }

        // Create root group
        let targetGroupID: NSManagedObjectID? = try await context.perform {
            let rootGroup = parentGroupObjectID == nil
                ? Group(name: folderName, context: self.context)
                : nil

            if let rootGroup {
                self.context.insert(rootGroup)
                try self.context.save()
                return rootGroup.objectID
            } else {
                return parentGroupObjectID
            }
        }

        guard let targetGroupID = targetGroupID else {
            throw AppError.fileError(.notFound)
        }

        // Import files from folder
        let folderOrURLs = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for url in folderOrURLs {
            guard let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                continue
            }

            if !isDirectory && url.pathExtension == "excalidraw" {
                // Create file using FileRepository
                _ = try await PersistenceController.shared.fileRepository.createFileFromURL(
                    url,
                    groupObjectID: targetGroupID
                )
            }
        }

        // Recursively import subfolders
        for childObjectID in childrenObjectIDs {
            // Create child group
            let childGroupID = try await importToGroup(
                localFolderObjectID: childObjectID,
                delete: false,
                parentGroupObjectID: nil
            )

            // Add child group to parent
            try await context.perform {
                guard let targetGroup = self.context.object(with: targetGroupID) as? Group,
                      let childGroup = self.context.object(with: childGroupID) as? Group else {
                    return
                }
                targetGroup.addToChildren(childGroup)
                try self.context.save()
            }
        }

        // Delete folder if requested
        if delete {
            let fileCoordinator = NSFileCoordinator()
            fileCoordinator.coordinate(
                writingItemAt: folderURL,
                options: .forMoving,
                error: nil
            ) { url in
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }

        return targetGroupID
    }
}
