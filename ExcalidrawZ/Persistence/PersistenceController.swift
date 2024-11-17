//
//  PersistenceController.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/6.
//

import Foundation
import CoreData

struct PersistenceController {
    // A singleton for our entire app to use
    static let shared = PersistenceController()

    // Storage for Core Data
    let container: NSPersistentContainer

    // An initializer to load Core Data, optionally able
    // to use an in-memory store.
    init(inMemory: Bool = false) {
        // If you didn't name your model Main you'll need
        // to change this name below.
        container = NSPersistentContainer(name: "Model")
        container.viewContext.automaticallyMergesChangesFromParent = true
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        
        #if DEBUG
//        log()
        #endif
        
        prepare()
        migration()
    }
    
    func prepare() {
        Task {
            do {
                let fetch: NSFetchRequest<Group> = NSFetchRequest(entityName: "Group")
                
                try await container.viewContext.perform {
                    let groups = try fetch.execute()
                    if groups.first(where: {$0.groupType == .default}) == nil {
                        // create the default group
                        let group = Group(context: container.viewContext)
                        group.id = UUID()
                        group.name = "default"
                        group.createdAt = .now
                        group.groupType = .default
                    }
                    
                    if groups.first(where: {$0.groupType == .default}) == nil {
                        let group = Group(context: container.viewContext)
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
}

extension PersistenceController {
    func listGroups() throws -> [Group] {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.sortDescriptors = [.init(key: "createdAt", ascending: true)]
        return try container.viewContext.fetch(fetchRequest)
    }
    func listFiles(in group: Group) throws -> [File] {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
        fetchRequest.sortDescriptors = [ .init(key: "updatedAt", ascending: false),
                                         .init(key: "createdAt", ascending: false)]
        return try container.viewContext.fetch(fetchRequest)
    }
    func listTrashedFiles() throws -> [File] {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == YES")
        fetchRequest.sortDescriptors = [.init(key: "deletedAt", ascending: false)] 
        return try container.viewContext.fetch(fetchRequest)
    }
    func findGroup(id: UUID) throws -> Group? {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id.uuidString)
        return try container.viewContext.fetch(fetchRequest).first
    }
    func getDefaultGroup() throws -> Group? {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
        return try container.viewContext.fetch(fetchRequest).first
    }
    func findFile(id: UUID) throws -> File? {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try container.viewContext.fetch(fetchRequest).first
    }
    
    func listAllFiles() throws -> [String : [File]] {
        let groups = try listGroups()
        var results: [String : [File]] = [:]
        for group in groups {
            guard let name = group.name else { continue }
            var renameI = 1
            var newName = name
            while results[newName] != nil {
                newName = "\(name) (\(renameI))"
                renameI += 1
            }
            results[newName] = try listFiles(in: group)
        }
        return results
    }
    
//    func createGroup(name: String, context: NSManagedObjectContext) throws -> Group {
//        let group = Group(context: context)
//        group.id = UUID()
//        group.name = name
//        group.createdAt = .now
//        return group
//    }
    
    @MainActor
    func createFile(in group: Group) throws -> File {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { throw AppError.fileError(.notFound) }
        
        let file = File(context: container.viewContext)
        file.id = UUID()
        file.name = String(localizable: .newFileNamePlaceholder)
        file.createdAt = .now
        file.updatedAt = .now
        file.group = group
        file.content = try Data(contentsOf: templateURL)
        return file
    }
    
    @MainActor
    func duplicateFile(file: File) -> File {
        let newFile = File(context: container.viewContext)
        newFile.id = UUID()
        newFile.createdAt = .now
        newFile.updatedAt = .now
        newFile.name = file.name
        newFile.content = file.content
        newFile.group = file.group
        return newFile
    }
    
    //MARK: - Checkpoints
    
    func getLatestCheckpoint(of file: File, viewContext: NSManagedObjectContext) throws -> FileCheckpoint? {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
        return try viewContext.fetch(fetchRequest).first
    }
    
    func getOldestCheckpoint(of file: File) throws -> FileCheckpoint? {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: true)]
        return try container.viewContext.fetch(fetchRequest).first
    }
    
    func fetchFileCheckpoints(of file: File, viewContext: NSManagedObjectContext) throws -> [FileCheckpoint] {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
        return try viewContext.fetch(fetchRequest)
    }
    
    
    
    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Show some error here
                dump(error)
            }
        } else {
            print("[Persistance Controller] nothing changed")
        }
    }
}


// MARK: Migration
extension PersistenceController {
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
                    
                    let needBackup: Bool = {
                        let excalidrawFiles = files.compactMap {
                            try? ExcalidrawFile(from: $0)
                        } + checkpoints.compactMap {
                            try? ExcalidrawFile(from: $0)
                        }
                        return excalidrawFiles.contains(where: {!$0.files.isEmpty})
                    }()
                    
                    if needBackup {
                        do {
                            try backupFiles()
//                            let backupsDir = try getBackupsDir()
//                            let backupDir = backupsDir.appendingPathComponent("Backup-Before-Media-Migration", conformingTo: .directory)
//                            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: false)
//                            try archiveAllFiles(to: backupDir)
                        } catch {
                            print(error)
                        }
                    }
                    
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
                                container.viewContext.insert(mediaItem)
                                insertedMediaID.insert(id)
                            }
                            file.content = try excalidrawFile.contentWithoutFiles()
//                            if let content = file.content,
//                               var jsonObj = try JSONSerialization.jsonObject(with: content) as? [String : Any] {
//                                jsonObj.removeValue(forKey: "files")
//                                file.content = try JSONSerialization.data(withJSONObject: jsonObj)
//                            }
                        } catch {
                            continue
                        }
                    }
                    print("Need migrate \(checkpoints.count) checkpoints")
                    for checkpoint in checkpoints {
                        guard let data = checkpoint.content else { continue }
                        do {
                            let excalidrawFile = try ExcalidrawFile(data: data)
                            if excalidrawFile.files.isEmpty { continue }
                            print("migrating \(excalidrawFile.files.count) files of checkpoint<\(checkpoint.file?.name ?? "Untitled")>")
                            for (id, media) in excalidrawFile.files {
                                if insertedMediaID.contains(id) { continue }
                                let mediaItem = MediaItem(resource: media, context: context)
                                mediaItem.file = checkpoint.file
                                container.viewContext.insert(mediaItem)
                            }
                            checkpoint.content = try excalidrawFile.contentWithoutFiles()
//                            if let content = checkpoint.content,
//                               var jsonObj = try JSONSerialization.jsonObject(with: content) as? [String : Any] {
//                                jsonObj.removeValue(forKey: "files")
//                                checkpoint.content = try JSONSerialization.data(withJSONObject: jsonObj)
//                            }
                        } catch {
                            continue
                        }
                    }
                    
                }
                print("🎉🎉🎉 Migration medias done. Time cost: \(-start.timeIntervalSinceNow) s")
                

            } catch {
                print(error)
            }
        }
    }
}

extension NSManagedObjectContext {
    /// Executes the given `NSBatchDeleteRequest` and directly merges the changes to bring the given managed object context up to date.
    ///
    /// - Parameter batchDeleteRequest: The `NSBatchDeleteRequest` to execute.
    /// - Throws: An error if anything went wrong executing the batch deletion.
    public func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}

#if DEBUG
extension PersistenceController {
    // A test configuration for SwiftUI previews
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)

        // Create 10 example programming languages.
//        for _ in 0..<10 {
//            let language = ProgrammingLanguage(context: controller.container.viewContext)
//            language.name = "Example Language 1"
//            language.creator = "A. Programmer"
//        }

        return controller
    }()
    
    func log() {
        Task {
            do {
                let filesFetch: NSFetchRequest<File> = NSFetchRequest(entityName: "File")
                let groupsFetch: NSFetchRequest<Group> = NSFetchRequest(entityName: "Group")
                
                try await container.viewContext.perform {
                    let files = try filesFetch.execute()
                    let groups = try groupsFetch.execute()
                    dump(groups, name: "groups")
                    dump(files, name: "files")
                }
                
            } catch {
                dump(error, name: "migration failed")
            }
        }
    }
}
#endif

