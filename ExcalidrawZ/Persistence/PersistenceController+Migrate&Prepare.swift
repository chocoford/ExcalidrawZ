//
//  PersistenceController+Migrate&Prepare.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import Foundation
import CoreData

extension PersistenceController {
    func prepare() {
        Task {
            do {
                let fetch: NSFetchRequest<Group> = NSFetchRequest(entityName: "Group")
                
                try await container.viewContext.perform {
                    let groups = try fetch.execute()
                    if groups.first(where: {$0.groupType == .default}) == nil {
                        // create the default group
                        let group = Group(context: self.container.viewContext)
                        group.id = UUID()
                        group.name = "default"
                        group.createdAt = .now
                        group.groupType = .default
                    }
                    
                    if groups.first(where: {$0.groupType == .default}) == nil {
                        let group = Group(context: self.container.viewContext)
                        group.id = UUID()
                        group.name = "Recently deleted"
                        group.createdAt = .now
                        group.groupType = .trash
                    }
                }
                
            } catch {
                dump(error, name: "fetch groups failed")
            }
        }
    }
    
    func migration() {
        let context = container.viewContext
        Task {
            // Make all old trashed file to 'source from default group'
            do {
                let filesFetch: NSFetchRequest<File> = NSFetchRequest(entityName: "File")
                let groupsFetch: NSFetchRequest<Group> = NSFetchRequest(entityName: "Group")
                
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
                dump(error, name: "migration failed")
            }
            
            do {
                let start = Date()
                print("🕘🕘🕘 Begin migrate medias. ")
                let filesFetch: NSFetchRequest<File> = NSFetchRequest(entityName: "File")
                let checkpointsFetch: NSFetchRequest<FileCheckpoint> = NSFetchRequest(entityName: "FileCheckpoint")

                try await context.perform {
                    let files = try filesFetch.execute()
                    let checkpoints = try checkpointsFetch.execute()
                    
                    let needMigrate: Bool = {
                        let excalidrawFiles = files.compactMap {
                            try? ExcalidrawFile(from: $0)
                        } + checkpoints.compactMap {
                            try? ExcalidrawFile(from: $0)
                        }
                        return excalidrawFiles.contains(where: {!$0.files.isEmpty})
                    }()
                    guard needMigrate else {
                        print("No need to migrate, skip")
                        return
                    }
#if os(macOS)
                    do {
                        try backupFiles(context: context)
                    } catch {
                        print(error)
                    }
#endif
                    var insertedMediaID = Set<String>()
                    print("Need migrate \(files.count) files")
                    for file in files {
                        do {
                            let excalidrawFile = try ExcalidrawFile(from: file)
                            if excalidrawFile.files.isEmpty { continue }
                            print("migrating \(excalidrawFile.files.count) files of \(excalidrawFile.name ?? "Untitled")")
                            for (id, media) in excalidrawFile.files {
                                if insertedMediaID.contains(id) { continue }
                                
                                let mediaItem = MediaItem(resource: media, context: context)
                                mediaItem.file = file
                                self.container.viewContext.insert(mediaItem)
                                insertedMediaID.insert(id)
                            }
                            file.content = try excalidrawFile.contentWithoutFiles()
                        } catch {
                            print("⚠️⚠️⚠️File migration failed. name: \(String(describing: file.name)), content: \(String(describing: try? JSONSerialization.jsonObject(with: file.content ?? Data())))")
                            continue
                        }
                    }
                    print("Need migrate \(checkpoints.count) checkpoints")
                    for checkpoint in checkpoints {
                        do {
                            guard let data = checkpoint.content else {
                                struct NoContentError: LocalizedError { var errorDescription: String? { "Checkpoint has no content data." } }
                                throw NoContentError()
                            }
                            let excalidrawFile = try ExcalidrawFile(data: data)
                            if excalidrawFile.files.isEmpty { continue }
                            print("migrating \(excalidrawFile.files.count) files of checkpoint<\(checkpoint.file?.name ?? "Untitled")>")
                            for (id, media) in excalidrawFile.files {
                                if insertedMediaID.contains(id) { continue }
                                let mediaItem = MediaItem(resource: media, context: context)
                                mediaItem.file = checkpoint.file
                                self.container.viewContext.insert(mediaItem)
                            }
                            checkpoint.content = try excalidrawFile.contentWithoutFiles()
                        } catch {
                            print("⚠️⚠️⚠️Checkpoint migration failed. file name: \(String(describing: checkpoint.file?.name)), content: \(String(describing: try? JSONSerialization.jsonObject(with: checkpoint.file?.content ?? Data())))")
                            continue
                        }
                    }
                    print("🎉🎉🎉 Migration medias done. Time cost: \(-start.timeIntervalSinceNow) s")
                }
            } catch {
                print(error)
            }
        }
    }
}
