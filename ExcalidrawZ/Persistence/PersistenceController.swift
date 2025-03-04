//
//  PersistenceController.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/6.
//

import Foundation
import CoreData

struct PersistenceController {
    static let shared = PersistenceController(cloudKitEnabled: !UserDefaults.standard.bool(forKey: "DisableCloudSync"))
    let container: NSPersistentContainer

    /// Init function
    /// - Parameters:
    ///   - inMemory: inMemory
    ///   - cloudKitEnabled: Enabled status for app internal.
    init(inMemory: Bool = false, cloudKitEnabled: Bool = true) {
        print("[PersistenceController] init with\(cloudKitEnabled ? "" : "out") cloudKit")
        if cloudKitEnabled {
            container = NSPersistentCloudKitContainer(name: "Model")
        } else {
            container = NSPersistentContainer(name: "Model")
        }
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        let storeDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ExcalidrawZ", conformingTo: .directory)
        
        if !FileManager.default.fileExists(at: storeDir) {
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: false)
        }
        
        let cloudStoreDescription: NSPersistentStoreDescription = if inMemory {
            NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            // Historical reason
            NSPersistentStoreDescription(
                url: container.persistentStoreDescriptions.first?.url ??
                storeDir.appendingPathComponent("Model.sqlite")
            )
        }
        cloudStoreDescription.configuration = "Cloud"
        cloudStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.chocoford.excalidraw"
        )
        cloudStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        let localStoreLocation = storeDir
            .appendingPathComponent("ExcalidrawZLocal.sqlite")
        let localStoreDescription: NSPersistentStoreDescription = if inMemory {
            NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            NSPersistentStoreDescription(url: localStoreLocation)
        }
        localStoreDescription.configuration = "Local"
        
        container.persistentStoreDescriptions = [
            cloudStoreDescription,
            localStoreDescription
        ]
        print(container.persistentStoreDescriptions)
        container.viewContext.automaticallyMergesChangesFromParent = true
        /// Core Data 预设了四种合并冲突策略，分别为：
        /// * NSMergeByPropertyStoreTrumpMergePolicy
        /// 逐属性比较，如果持久化数据和内存数据都改变且冲突，持久化数据胜出
        /// * NSMergeByPropertyObjectTrumpMergePolicy
        /// 逐属性比较，如果持久化数据和内存数据都改变且冲突，内存数据胜出
        /// * NSOverwriteMergePolicy
        /// 内存数据永远胜出
        /// * NSRollbackMergePolicy
        /// 持久化数据永远胜出
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        do {
              try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
             fatalError("Failed to pin viewContext to the current generation:\(error)")
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                print(error)
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
    func listFiles(in group: Group, context: NSManagedObjectContext) throws -> [File] {
        if group.groupType == .trash {
            return try listTrashedFiles(context: context)
        }
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
        fetchRequest.sortDescriptors = [ .init(key: "updatedAt", ascending: false),
                                         .init(key: "createdAt", ascending: false)]
        return try context.fetch(fetchRequest)
    }
    func listTrashedFiles(context: NSManagedObjectContext) throws -> [File] {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == YES")
        fetchRequest.sortDescriptors = [.init(key: "deletedAt", ascending: false)] 
        return try context.fetch(fetchRequest)
    }
    func findGroup(id: UUID) throws -> Group? {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id.uuidString)
        return try container.viewContext.fetch(fetchRequest).first
    }
    func getDefaultGroup(context: NSManagedObjectContext) throws -> Group? {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
        return try context.fetch(fetchRequest).first
    }
    func findFile(id: UUID) throws -> File? {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try container.viewContext.fetch(fetchRequest).first
    }
    
    func listAllFiles(context: NSManagedObjectContext) throws -> [String : [File]] {
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
            results[newName] = try listFiles(in: group, context: context)
        }
        return results
    }
    
    @MainActor
    func createFile(in groupID: NSManagedObjectID, context: NSManagedObjectContext) throws -> File {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { throw AppError.fileError(.notFound) }
        
        let file = File(context: context)
        file.id = UUID()
        file.name = String(localizable: .newFileNamePlaceholder)
        file.createdAt = .now
        file.updatedAt = .now
        guard let group = context.object(with: groupID) as? Group else {
            throw AppError.groupError(.notFound(groupID.description))
        }
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
                                container.viewContext.insert(mediaItem)
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
                                container.viewContext.insert(mediaItem)
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

