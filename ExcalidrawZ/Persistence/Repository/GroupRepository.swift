//
//  GroupRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/22.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for Group entity operations
actor GroupRepository {
    private let logger = Logger(label: "GroupRepository")
    
    // MARK: - Export Group

    /// Export group and all its contents to disk
    /// - Parameters:
    ///   - groupObjectID: The NSManagedObjectID of the group
    ///   - folderURL: The destination folder URL
    func exportToDisk(groupObjectID: NSManagedObjectID, folder folderURL: URL) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let fileManager = FileManager.default

        // Get group info
        let (groupName, fileObjectIDs, childGroupObjectIDs) = try await context.perform {
            guard let group = context.object(with: groupObjectID) as? Group else {
                throw AppError.fileError(.notFound)
            }

            let files = (group.files ?? []).compactMap { $0 as? File }
            let children = (group.children ?? []).compactMap { $0 as? Group }

            return (
                group.name ?? String(localizable: .generalUntitled),
                files.map { $0.objectID },
                children.map { $0.objectID }
            )
        }

        // Create folder with unique name
        var folderName = groupName
        var i = 1
        while fileManager.fileExists(
            atPath: folderURL.appendingPathComponent(folderName).filePath
        ) {
            folderName = groupName + " (\(i))"
            i += 1
        }

        let groupFolderURL = folderURL.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: groupFolderURL, withIntermediateDirectories: true)

        // Export all files in this group
        for fileObjectID in fileObjectIDs {
            try await PersistenceController.shared.fileRepository.exportToDisk(
                fileObjectID: fileObjectID,
                folder: groupFolderURL
            )
        }

        // Recursively export child groups
        for childGroupObjectID in childGroupObjectIDs {
            try await exportToDisk(groupObjectID: childGroupObjectID, folder: groupFolderURL)
        }
    }

    // MARK: - Delete Group

    /// Delete group (move files to default group or empty trash)
    /// - Parameters:
    ///   - groupObjectID: The NSManagedObjectID of the group
    ///   - forcePermanently: Whether to force permanent deletion
    ///   - save: Whether to save the context after deletion
    func delete(
        groupObjectID: NSManagedObjectID,
        forcePermanently: Bool = false,
        save: Bool = true
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let (groupType, fileObjectIDs, subGroupObjectIDs) = try await context.perform {
            guard let group = context.object(with: groupObjectID) as? Group else {
                throw AppError.fileError(.notFound)
            }

            let type = group.groupType
            var fileIDs: [NSManagedObjectID] = []
            var subGroupIDs: [NSManagedObjectID] = []

            if type == .trash {
                // Empty trash: get all trashed files
                let fetchRequest = NSFetchRequest<File>(entityName: "File")
                fetchRequest.predicate = File.trashedPredicate
                fileIDs = try context.fetch(fetchRequest).map { $0.objectID }
            } else {
                // Get files in this group and subgroups
                let fetchRequest = NSFetchRequest<File>(entityName: "File")
                fetchRequest.predicate = NSPredicate(format: "inTrash == FALSE AND group == %@", group)
                fileIDs = try context.fetch(fetchRequest).map { $0.objectID }

                let subGroupsFetchRequest = NSFetchRequest<Group>(entityName: "Group")
                subGroupsFetchRequest.predicate = NSPredicate(format: "parent == %@", group)
                subGroupIDs = try context.fetch(subGroupsFetchRequest).map { $0.objectID }
            }

            return (type, fileIDs, subGroupIDs)
        }

        if groupType == .trash {
            // Delete every metadata record in one transaction. Storage files
            // and other side effects are cleaned independently afterward, so
            // one already-missing file cannot leave the rest of Trash intact.
            logger.info("Emptying trash with \(fileObjectIDs.count) file(s)")
            try await PersistenceController.shared.fileRepository.delete(
                fileObjectIDs: fileObjectIDs,
                forcePermanently: true,
                save: true
            )
        } else {
            // Move files to default group and mark as deleted
            guard let defaultGroupObjectID = try await getDefaultGroupObjectID() else {
                throw AppError.fileError(.notFound)
            }

            // Move the files in one transaction before the source group is
            // deleted, then mark them as trashed in FileRepository's context.
            try await context.perform {
                guard let defaultGroup = context.object(with: defaultGroupObjectID) as? Group else {
                    throw AppError.fileError(.notFound)
                }
                for fileObjectID in fileObjectIDs {
                    guard let file = context.object(with: fileObjectID) as? File else {
                        continue
                    }
                    file.group = defaultGroup
                }
                try context.save()
            }

            if !fileObjectIDs.isEmpty {
                try await PersistenceController.shared.fileRepository.delete(
                    fileObjectIDs: fileObjectIDs,
                    forcePermanently: forcePermanently,
                    save: true
                )
            }

            // Recursively delete subgroups
            for subGroupObjectID in subGroupObjectIDs {
                try await delete(groupObjectID: subGroupObjectID, forcePermanently: forcePermanently, save: false)
            }

            // Delete the group itself
            try await context.perform {
                guard let group = context.object(with: groupObjectID) as? Group else { return }
                context.delete(group)
                try context.save()
            }
        }

        if save {
            try await context.perform {
                try context.save()
            }
        }
    }

    // MARK: - Create Groups

    /// Create a trash group if it doesn't exist
    /// - Returns: The objectID of the trash group (existing or newly created)
    func createTrashGroupIfNeeded() async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        // Check if trash group already exists
        let existingTrashObjectID: NSManagedObjectID? = try await context.perform {
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type == %@", Group.GroupType.trash.rawValue)
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Group.createdAt, ascending: true)
            ]
            fetchRequest.fetchLimit = 1

            guard let group = try context.fetch(fetchRequest).first else { return nil }

            var didChange = false
            if group.parent != nil {
                group.parent = nil
                didChange = true
            }
            if group.name?.isEmpty != false {
                group.name = "Recently Deleted"
                didChange = true
            }
            if didChange {
                try context.save()
            }

            return group.objectID
        }
        if let existingTrashObjectID {
            return existingTrashObjectID
        }

        // Create new trash group
        let trashObjectID = try await context.perform {
            let group = Group(context: context)
            group.id = UUID()
            group.groupType = .trash
            group.name = "Recently Deleted"
            group.createdAt = .now

            context.insert(group)
            try context.save()

            return group.objectID
        }

        logger.info("Created trash group")
        return trashObjectID
    }

    /// Create a default group if it doesn't exist
    /// - Returns: The objectID of the default group (existing or newly created)
    func createDefaultGroupIfNeeded() async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        // Check if default group already exists
        if let existingDefaultObjectID = try await getDefaultGroupObjectID() {
            return existingDefaultObjectID
        }

        // Create new default group
        let defaultObjectID = try await context.perform {
            let group = Group(context: context)
            group.id = UUID()
            group.groupType = .default
            group.name = "default"
            group.createdAt = .now

            context.insert(group)
            try context.save()

            return group.objectID
        }

        logger.info("Created default group")
        return defaultObjectID
    }

    // MARK: - Helper Methods

    /// Get the default group object ID
    private func getDefaultGroupObjectID() async throws -> NSManagedObjectID? {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type == %@", Group.GroupType.default.rawValue)
            fetchRequest.fetchLimit = 1
            return try context.fetch(fetchRequest).first?.objectID
        }
    }
}
