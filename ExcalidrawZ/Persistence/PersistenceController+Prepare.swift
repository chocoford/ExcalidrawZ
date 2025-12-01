//
//  PersistenceController+Migrate&Prepare.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import Foundation
@preconcurrency import CoreData

extension PersistenceController {
    func prepare() {
        Task {
            do {
                // Create default and trash groups if they don't exist
                _ = try await self.groupRepository.createDefaultGroupIfNeeded()
                _ = try await self.groupRepository.createTrashGroupIfNeeded()
            } catch {
                dump(error, name: "create groups failed")
            }

            // Fallback behavior: Move trashed files from trash group to default group
            do {
                let filesFetch: NSFetchRequest<File> = NSFetchRequest(entityName: "File")
                let groupsFetch: NSFetchRequest<Group> = NSFetchRequest(entityName: "Group")

                let context = self.newTaskContext()
                try await context.perform {
                    let files = try filesFetch.execute()
                    let groups = try groupsFetch.execute()

                    let defaultGroup = groups.first { $0.groupType == .default }

                    files.forEach { file in
                        if file.group?.groupType == .trash {
                            file.group = defaultGroup
                            file.inTrash = true
                            file.deletedAt = .now
                        }
                    }
                }
            } catch {
                dump(error, name: "prepare fallback failed")
            }
        }
    }
}
