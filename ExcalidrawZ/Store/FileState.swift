//
//  FileState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import os.log
import UniformTypeIdentifiers
import CoreData

final class FileState: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FileState")
    
    var stateUpdateQueue: DispatchQueue = DispatchQueue(label: "StateUpdateQueue")
    
    var currentGroupPublisherCancellables: [AnyCancellable] = []
    var currentFilePublisherCancellables: [AnyCancellable] = []
    
    @Published var currentGroup: Group? {
        didSet {
            currentGroupPublisherCancellables.forEach {$0.cancel()}
            guard let currentGroup else { return }
            currentGroupPublisherCancellables = [
                currentGroup.publisher(for: \.name).sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            ]
        }
    }
    @Published var currentFile: File? {
        didSet {
            print("freeze watchUpdate: \(Date.now.formatted(date: .omitted, time: .complete))")
            shouldIgnoreUpdate = true
            recoverWatchUpdate()
            currentFilePublisherCancellables.forEach{$0.cancel()}
            if let currentFile {
                currentFilePublisherCancellables = [
                    currentFile.publisher(for: \.name).sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.objectWillChange.send()
                        }
                    },
                    currentFile.publisher(for: \.updatedAt).sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.objectWillChange.send()
                        }
                    }
                ]
//                excalidrawWebCoordinator?.loadFile(from: currentFile)
            }
        }
    }
    
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    
    var shouldIgnoreUpdate = true
    /// Indicate the file is being updated after being set as current file.
    var didUpdateFile = false
    var isCreatingFile = false
    
    var recoverWatchUpdateWorkItem: DispatchWorkItem?
    
    private func recoverWatchUpdate() {
        recoverWatchUpdateWorkItem?.cancel()
        recoverWatchUpdateWorkItem = DispatchWorkItem(flags: .assignCurrentContext) {
            if self.excalidrawWebCoordinator?.isLoading == true {
                self.recoverWatchUpdate()
                return
            }
            print("recoverWatchUpdateWorkItem: \(Date.now.timeIntervalSince1970)")
            self.shouldIgnoreUpdate = false
            self.didUpdateFile = false
        }
        stateUpdateQueue.asyncAfter(deadline: .now().advanced(by: .milliseconds(2500)), execute: recoverWatchUpdateWorkItem!)
    }
    
    @discardableResult
    func createNewGroup(name: String, activate: Bool = true, context: NSManagedObjectContext) async throws -> NSManagedObjectID {
        try await context.perform {
            let group = Group(name: name, context: context)
            try context.save()
            if activate {
                DispatchQueue.main.async {
                    self.currentGroup = group
                }
            }
            return group.objectID
        }
    }
    
    func createNewFile(active: Bool = true, context: NSManagedObjectContext) throws {
        guard let currentGroup else { throw AppError.stateError(.currentGroupNil) }
        let file = File(name: String(localizable: .newFileNamePlaceholder), context: context)
        guard let group = context.object(with: currentGroup.objectID) as? Group else {
            throw AppError.groupError(.notFound(currentGroup.objectID.description))
        }
        file.group = group
        
        guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else {
            throw AppError.fileError(.notFound)
        }
        file.content = try Data(contentsOf: templateURL)
        if active {
            currentFile = file
        }
        try context.save()
    }
    
    func updateCurrentFileData(data: Data) {
        guard !shouldIgnoreUpdate, currentFile?.inTrash != true else {
            return
        }
        if let file = currentFile {
            let didUpdateFile = didUpdateFile
            let id = file.objectID
            let bgContext = PersistenceController.shared.container.newBackgroundContext()
            
            Task.detached {
                do {
                    try await bgContext.perform {
                        guard let file = bgContext.object(with: id) as? File else { return }
                        try file.updateElements(with: data, newCheckpoint: !didUpdateFile)
                        try bgContext.save()
                    }
                    
                    await MainActor.run {
                        self.didUpdateFile = true
                    }
                    
                } catch {
                    print(error)
                }
            }
        } else if !isCreatingFile {
            
        }
    }
    
    func updateCurrentFile(with excalidrawFile: ExcalidrawFile) {
        guard !shouldIgnoreUpdate, currentFile?.inTrash != true else {
            return
        }
        if let file = self.currentFile {
            let didUpdateFile = didUpdateFile
            let id = file.objectID
            let bgContext = PersistenceController.shared.container.newBackgroundContext()
            
            Task.detached {
                do {
                    try await bgContext.perform {
                        guard let file = bgContext.object(with: id) as? File,
                              let content = excalidrawFile.content else { return }
                        
                        try file.updateElements(
                            with: content,
                            newCheckpoint: !didUpdateFile
                        )
                        let newMedias = excalidrawFile.files.filter { (id, _) in
                            file.medias?.contains(where: {
                                ($0 as? MediaItem)?.id == id
                            }) != true
                        }
                        
                        // also update medias
                        for (_, resource) in newMedias {
                            let mediaItem = MediaItem(resource: resource, context: bgContext)
                            mediaItem.file = file
                            bgContext.insert(mediaItem)
                        }
                        
                        try bgContext.save()
                    }
                    
                    await MainActor.run {
                        self.didUpdateFile = true
                    }
                    
                } catch {
                    print(error)
                }
            }
        } else if !isCreatingFile {
            
        }
    }
    
    enum ImportGroupType: Hashable {
        case current
        case `default`
        case custom(Group.ID)
    }
    func importFile(_ url: URL, to targetGroupType: ImportGroupType = .current) async throws {
        let excalidrawFile = try ExcalidrawFile(contentsOf: url)
                var targetGroup: Group?
        if targetGroupType == .default {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
            fetchRequest.fetchLimit = 1
            try await viewContext.perform {
                let result = (try viewContext.fetch(fetchRequest).first) as Group?
                targetGroup = result
            }
        } else if case .custom(let id) = targetGroupType, let id {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1
            try await viewContext.perform {
                let result = (try viewContext.fetch(fetchRequest).first) as Group?
                targetGroup = result
            }
        }
        
        let group = targetGroup
        let viewContext = PersistenceController.shared.container.viewContext
        try await viewContext.perform {
            guard let group = group ?? self.currentGroup else { throw AppError.stateError(.currentGroupNil) }
            let file = File(name: excalidrawFile.name ?? "Untitled", context: viewContext)
            file.content = try excalidrawFile.contentWithoutFiles()
            file.group = group
            
            let mediaItems = try viewContext.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
            let mediaItemsNeedImport = excalidrawFile.files.values.filter{ item in !mediaItems.contains(where: {$0.id == item.id})}
            mediaItemsNeedImport.forEach { item in
                let mediaItem = MediaItem(resource: item, context: viewContext)
                mediaItem.file = file
                viewContext.insert(mediaItem)
            }
            PersistenceController.shared.save()

            DispatchQueue.main.async {
                Task {
                    try? await self.excalidrawWebCoordinator?.insertMediaFiles(mediaItemsNeedImport)
                }
                self.currentFile = file
            }
        }
    }
    
    /// Different handle logics according to different combinations of urls.
    /// * only files: Import to current group.
    /// * 1 folder:
    ///     * if has subfolders: Create groups by folders & Group remains files to `Ungrouped`
    ///     * if only files: import all files to one group with the same name of the ancestor folder.
    /// * multiple folders: Create groups by folders
    /// * folders & files: Create groups by folders & Group remains files to `Ungrouped`
    func importFiles(_ urls: [URL]) async throws {
        let currentGroupID = currentGroup?.objectID
        var groupID: NSManagedObjectID?
        if urls.count == 1, let url = urls.first {
            if FileManager.default.isDirectory(url) { // a directory
                let viewContext = PersistenceController.shared.container.newBackgroundContext()
                try await viewContext.perform {
                    let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [])
                    
                    if contents.allSatisfy({!FileManager.default.isDirectory($0)}) {
                        // only files
                        groupID = try self.importGroupFiles(url: url, viewContext: viewContext)
                    } else {
                        // has subfolders
                        var unknownGroup: Group?
                        for url in contents {
                            if FileManager.default.isDirectory(url) {
                                try self.importGroupFiles(url: url, viewContext: viewContext)
                            } else if url.pathExtension == UTType.excalidrawFile.preferredFilenameExtension {
                                if unknownGroup == nil {
                                    unknownGroup = Group(name: "Ungrouped", context: viewContext)
                                }
                                let data = try Data(contentsOf: url, options: .uncached)
                                let file = File(name: url.deletingPathExtension().lastPathComponent, context: viewContext)
                                file.content = data
                                file.group = unknownGroup
                            }
                        }
                    }
                    try viewContext.save()
                }
            } else {
                // only one excalidraw file
                try await self.importFile(url)
            }
        } else if urls.count > 1 {
            // folders will be created as group, files will be imported to `default` group.
            let viewContext = PersistenceController.shared.container.newBackgroundContext()
            try await viewContext.perform {
                let fetchRequest = NSFetchRequest<Group>()
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                var group: Group?
                if let currentGroupID, let currentGroup = viewContext.object(with: currentGroupID) as? Group {
                    group = currentGroup
                } else if let defaultGroup = try viewContext.fetch(fetchRequest).first {
                    group = defaultGroup
                }
                guard let group else { return }
                // multiple folders
                for folderURL in urls.filter({FileManager.default.isDirectory($0)}) {
                    try self.importGroupFiles(url: folderURL, viewContext: viewContext)
                }
                // only files
                for fileURL in urls.filter({!FileManager.default.isDirectory($0)}) {
                    let data = try Data(contentsOf: fileURL, options: .uncached)
                    let file = File(name: fileURL.deletingPathExtension().lastPathComponent, context: viewContext)
                    file.content = data
                    file.group = group
                }
                try viewContext.save()
                
                groupID = group.objectID
            }
        }
//        await PersistenceController.shared.container.viewContext.perform {
//            if let groupID, let group = PersistenceController.shared.container.viewContext.object(with: groupID) as? Group {
//                DispatchQueue.main.async {
//                    self.currentGroup = group
//                }
//            }
//        }
        _ = groupID
    }
    
    @discardableResult
    private func importGroupFiles(url: URL, viewContext: NSManagedObjectContext) throws -> NSManagedObjectID {
        let groupName = url.lastPathComponent
        // create group
        let group = Group(name: groupName, context: viewContext)
        let urls = try flatFiles(in: url).filter {
            $0.pathExtension == UTType.excalidrawFile.preferredFilenameExtension
        }
        
        // Import medias
        let allMediaItems = try viewContext.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        var insertedMediaID = Set<String>()
        
        for url in urls {
            let excalidrawFile = try ExcalidrawFile(contentsOf: url)

            let file = File(name: excalidrawFile.name ?? "Untitled", context: viewContext)
            file.content = try excalidrawFile.contentWithoutFiles()
            file.group = group
            
            // Import medias
            let mediasToImport = excalidrawFile.files.values.filter { item in
                !insertedMediaID.contains(item.id) &&
                !allMediaItems.contains(where: {$0.id == item.id})
            }
            mediasToImport.forEach { item in
                let mediaItem = MediaItem(resource: item, context: viewContext)
                mediaItem.file = file
                viewContext.insert(mediaItem)
                insertedMediaID.insert(item.id)
            }
            Task {
                try? await self.excalidrawWebCoordinator?.insertMediaFiles(mediasToImport)
            }
        }
        
        return group.objectID
    }
    @MainActor
    func renameFile(_ file: File, newName: String) {
        file.name = newName
        PersistenceController.shared.save()
        self.objectWillChange.send()
    }
    
    func renameGroup(_ group: Group, newName: String) {
        group.name = newName
        PersistenceController.shared.save()
        self.objectWillChange.send()
    }
    
    func moveFile(_ file: File, to group: Group) {
        file.group = group
        if file == currentFile {
            currentGroup = group
            currentFile = file
        }
        PersistenceController.shared.save()
    }
    
    @discardableResult
    func duplicateFile(_ file: File, context: NSManagedObjectContext) throws -> File {
        let newFile = File(context: context)
        newFile.id = UUID()
        newFile.createdAt = .now
        newFile.updatedAt = .now
        newFile.name = file.name
        newFile.content = file.content
        newFile.group = file.group
        try context.save()
        
        return newFile
    }
    
    func deleteFile(_ file: File) {
        file.inTrash = true
        if file == currentFile {
            currentFile = nil
        }
        PersistenceController.shared.save()
    }
    
    func recoverFile(_ file: File) {
        guard file.inTrash else { return }
        file.inTrash = false
        
        currentGroup = file.group
        currentFile = file
        PersistenceController.shared.save()
    }

    func deleteFilePermanently(_ file: File) {
        PersistenceController.shared.container.viewContext.delete(file)
        PersistenceController.shared.save()
        if file == currentFile {
            currentFile = nil
        }
    }
    
    func deleteGroup(_ group: Group) throws {
        if group.groupType == .trash {
            let files = try PersistenceController.shared.listTrashedFiles()
            files.forEach { PersistenceController.shared.container.viewContext.delete($0) }
        } else {
            guard let defaultGroup = try PersistenceController.shared.getDefaultGroup() else { throw AppError.fileError(.notFound) }
            let groupFiles: [File] = group.files?.allObjects as? [File] ?? []
            for file in groupFiles {
                file.inTrash = true
                file.deletedAt = .now
                file.group = defaultGroup
            }
            PersistenceController.shared.container.viewContext.delete(group)
        }
        PersistenceController.shared.save()
        
        if group == currentGroup {
            currentGroup = nil
        }
    }
    
    func mergeDefaultGroupAndTrashIfNeeded(context: NSManagedObjectContext) async throws {
        try await context.perform {
            let groups = try context.fetch(NSFetchRequest<Group>(entityName: "Group"))
            
            let defaultGroups = groups.filter({$0.groupType == .default})
            
            // Merge default groups
            if defaultGroups.count > 1 {
                let theEearlisetGroup = defaultGroups.sorted(by: {
                    ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
                }).first!
                
                try defaultGroups.forEach { group in
                    if group != theEearlisetGroup {
                        let defaultGroupFilesfetchRequest = NSFetchRequest<File>(entityName: "File")
                        defaultGroupFilesfetchRequest.predicate = NSPredicate(format: "group == %@", group)
                        let defaultGroupFiles = try context.fetch(defaultGroupFilesfetchRequest)
                        defaultGroupFiles.forEach { file in
                            file.group = theEearlisetGroup
                        }
                        context.delete(group)
                    }
                }
                
                DispatchQueue.main.async {
                    self.currentGroup = theEearlisetGroup
                }
            }
            
            let trashGroups = groups.filter({$0.groupType == .trash})
            trashGroups.dropFirst().forEach { trash in
                context.delete(trash)
            }
            try context.save()
        }
    }
}
