//
//  Group.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import Foundation
import CoreData

#if DEBUG
extension Group {
    static let preview = {
        let group = Group(context: PersistenceController.preview.container.viewContext)
        group.id = UUID()
        group.name = "preview"
        group.createdAt = .now
        return group
    }()
}
#endif

extension Group {
    static let trash = {
        let group = Group(context: PersistenceController.shared.container.viewContext)
        group.id = UUID()
        group.groupType = .trash
        group.name = "Recently Deleted"
        group.createdAt = .distantPast
        return group
    }()
    
    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = .now
    }
    
    enum GroupType: String {
        case `default` = "default"
        case trash = "trash"
        case normal = "normal"
        
        var rank: Int {
            switch self {
                case .default:
                    return 0
                case .trash:
                    return 9999
                case .normal:
                    return 1
            }
        }
    }
    
    var groupType: GroupType {
        get {
            return GroupType(rawValue: self.type ?? "normal") ?? .normal
        }
        set {
            self.type = newValue.rawValue
        }
    }
    
    func exportToDisk(folder url: URL) throws {
        let filemanager = FileManager.default
        
        var folderName = self.name ?? String(localizable: .generalUntitled)
        var i = 1
        while filemanager.fileExists(
            atPath: url.appendingPathComponent(folderName).filePath
        ) {
            folderName = folderName + " (\(i))"
            i += 1
        }
        
        try filemanager.createDirectory(at: url.appendingPathComponent(folderName), withIntermediateDirectories: true)
        
        for case let file as File in files ?? [] {
            file.exportToDisk(folder: url)
        }
        
        for case let group as Group in children ?? [] {
            try group.exportToDisk(folder: url.appendingPathComponent(folderName))
        }
    }
    
    func delete(context: NSManagedObjectContext, save: Bool = true) throws {
        if groupType == .trash {
            // empty trash
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "inTrash == YES")
            for file in try context.fetch(fetchRequest) {
                try file.delete(context: context, save: false)
            }
        } else {
            // get default group
            guard let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context) else {
                throw AppError.fileError(.notFound)
            }
            
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(
                format: "inTrash == FALSE AND group == %@",
                self
            )
            for file in try context.fetch(fetchRequest) {
                file.group = defaultGroup
                try file.delete(context: context, save: false)
            }
            
            // delete sub groups
            let subGroupsFetchRequest = NSFetchRequest<Group>(entityName: "Group")
            subGroupsFetchRequest.predicate = NSPredicate(format: "parent == %@", self)
            for subGroup in try context.fetch(subGroupsFetchRequest) {
                try subGroup.delete(context: context, save: false)
            }
            
            context.delete(self)
        }
        if save {
            try context.save()
        }
    }
}

extension Group.GroupType: Comparable {
    static func < (lhs: Group.GroupType, rhs: Group.GroupType) -> Bool {
        return lhs.rank < rhs.rank
    }
}



// MARK: - Transformers
