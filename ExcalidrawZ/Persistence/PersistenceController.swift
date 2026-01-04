//
//  PersistenceController.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/6.
//

import Foundation
@preconcurrency import CoreData
import Logging

class PersistenceController {
    static let shared = {
        let cloudKitEnabled = !UserDefaults.standard.bool(forKey: "DisableCloudSync")
        let stack = PersistenceController(cloudKitEnabled: cloudKitEnabled)
        stack.prepare()
        return stack
    }()
    
    let container: NSPersistentContainer

    private(set) var spotlightIndexer: SpotlightDelegate?
    let cloudSpotlightDelegate: NSCoreDataCoreSpotlightDelegate
    let localSpotlightDelegate: NSCoreDataCoreSpotlightDelegate
    
    let logger = Logger(label: "PersistenceController")

    lazy var fileRepository: FileRepository = FileRepository(context: self.newTaskContext())
    lazy var checkpointRepository = CheckpointRepository(context: self.newTaskContext())
    lazy var mediaItemRepository = MediaItemRepository(context: self.newTaskContext())
    lazy var groupRepository = GroupRepository(context: self.newTaskContext())
    lazy var collaborationFileRepository = CollaborationFileRepository(context: self.newTaskContext())
    lazy var localFolderRepository = LocalFolderRepository(context: self.newTaskContext())
    
    /// Init function
    /// - Parameters:
    ///   - inMemory: inMemory
    ///   - cloudKitEnabled: Enabled status for app internal.
    init(inMemory: Bool = false, cloudKitEnabled: Bool = true) {
        self.logger.info("[PersistenceController] init with\(cloudKitEnabled ? "" : "out") cloudKit")
        if cloudKitEnabled {
            container = NSPersistentCloudKitContainer(name: "Model")
        } else {
            container = NSPersistentContainer(name: "Model")
        }
        
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
        cloudStoreDescription.type = NSSQLiteStoreType
        cloudStoreDescription.configuration = "Cloud"

        // Only configure CloudKit options when CloudKit is enabled
        if cloudKitEnabled {
            cloudStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.chocoford.excalidraw"
            )
        }

        cloudStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        cloudStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        let localStoreLocation = storeDir.appendingPathComponent("ExcalidrawZLocal.sqlite")
        let localStoreDescription: NSPersistentStoreDescription = if inMemory {
            NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            NSPersistentStoreDescription(url: localStoreLocation)
        }
        localStoreDescription.type = NSSQLiteStoreType
        localStoreDescription.configuration = "Local"
        localStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        localStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        container.persistentStoreDescriptions = [
            cloudStoreDescription,
            localStoreDescription
        ]
        // print(container.persistentStoreDescriptions, container.persistentStoreDescriptions.map{$0.type})
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
        
        // spotlightDelegate
        self.cloudSpotlightDelegate = SpotlightDelegate(
            forStoreWith: cloudStoreDescription,
            coordinator: container.persistentStoreCoordinator
        )
        self.cloudSpotlightDelegate.startSpotlightIndexing()
        self.localSpotlightDelegate = SpotlightDelegate(
            forStoreWith: localStoreDescription,
            coordinator: container.persistentStoreCoordinator
        )
//        self.localSpotlightDelegate.startSpotlightIndexing()
        #if DEBUG
//        log()
        #endif
    }
    
    func newTaskContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }
}

extension PersistenceController {
    struct ExcalidrawGroup: Hashable {
        var group: Group
        var ancestors: [Group]
        var children: [ExcalidrawGroup]
    }
    
    func listGroups(
        context: NSManagedObjectContext,
        ancestors: [Group] = []
    ) throws -> [ExcalidrawGroup] {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        if let parent = ancestors.last {
            fetchRequest.predicate = NSPredicate(format: "parent = %@", parent)
        } else {
            fetchRequest.predicate = NSPredicate(format: "parent = nil")
        }
        fetchRequest.sortDescriptors = [.init(key: "createdAt", ascending: true)]
        
        let groups = try context.fetch(fetchRequest)
        
        return try groups.map {
            try ExcalidrawGroup(
                group: $0,
                ancestors: ancestors,
                children: listGroups(context: context, ancestors: ancestors + [$0])
            )
        }
    }
    func listFiles(in group: Group, context: NSManagedObjectContext) throws -> [File] {
        if group.groupType == .trash {
            return try listTrashedFiles(context: context)
        }
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
        fetchRequest.sortDescriptors = [
            .init(key: "updatedAt", ascending: false),
            .init(key: "createdAt", ascending: false)
        ]
        return try context.fetch(fetchRequest)
    }
    func listTrashedFiles(context: NSManagedObjectContext) throws -> [File] {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == YES")
        fetchRequest.sortDescriptors = [
            .init(key: "deletedAt", ascending: false)
        ]
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
    
    func listAllFiles(
        context: NSManagedObjectContext,
        children: [ExcalidrawGroup]? = nil
    ) throws -> [ExcalidrawGroup : [File]] {
        let groups: [ExcalidrawGroup] = try children ?? listGroups(context: context)
        var results: [ExcalidrawGroup : [File]] = [:]
        for group in groups {
            results[group] = try listFiles(in: group.group, context: context)
            results = try results.merging(
                listAllFiles(context: context, children: group.children),
                uniquingKeysWith: { lhs, _ in lhs }
            )
        }
        return results
    }

    @MainActor
    func createFile(in groupID: NSManagedObjectID, context: NSManagedObjectContext) throws -> File {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else {
            throw AppError.fileError(.notFound)
        }
        
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
    //MARK: - Checkpoints
    @available(*, deprecated, message: "")
    func getLatestCheckpoint(of file: File, context: NSManagedObjectContext) throws -> FileCheckpoint? {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
        return try context.fetch(fetchRequest).first
    }
    func getLatestCheckpoint(of file: CollaborationFile, context: NSManagedObjectContext) throws -> FileCheckpoint? {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "collaborationFile == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
        return try context.fetch(fetchRequest).first
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
    func fetchFileCheckpoints(of file: CollaborationFile, context: NSManagedObjectContext) throws -> [FileCheckpoint] {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "collaborationFile == %@", file)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
        return try context.fetch(fetchRequest)
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

