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

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        
        prepare()
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
        fetchRequest.predicate = NSPredicate(format: "group == %@", group)
        fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false), .init(key: "createdAt", ascending: false)]
        return try container.viewContext.fetch(fetchRequest)
    }
    func findGroup(id: UUID) throws -> Group? {
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id.uuidString)
        return try container.viewContext.fetch(fetchRequest).first
    }
    func findFile(id: UUID) throws -> File? {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id.uuidString)
        return try container.viewContext.fetch(fetchRequest).first
    }
    
    
    func createGroup(name: String) throws -> Group {
        let group = Group(context: container.viewContext)
        group.id = UUID()
        group.name = name
        group.createdAt = .now
        
        return group
    }
    
    func createFile(in group: Group) throws -> File {
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { throw AppError.fileError(.notFound) }
        
        let file = File(context: container.viewContext)
        file.id = UUID()
        file.name = "Untitled"
        file.createdAt = .now
        file.group = group
        file.content = try Data(contentsOf: templateURL)
        return file
    }
    
    func duplicateFile(file: File) -> File {
        let newFile = File(context: container.viewContext)
        newFile.id = UUID()
        newFile.createdAt = .now
        newFile.name = file.name
        newFile.content = file.content
        newFile.group = file.group
        return newFile
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
        }
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
}
#endif

