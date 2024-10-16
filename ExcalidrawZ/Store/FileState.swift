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
            print("freeze watchUpdate: \(Date.now.timeIntervalSince1970)")
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
            }
        }
    }
//    @Published var currentFileID: UUID?
    
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
    func createNewGroup(name: String, activate: Bool = true) async throws -> NSManagedObjectID {
        try await PersistenceController.shared.container.viewContext.perform {
            let group = Group(name: name, context: PersistenceController.shared.container.viewContext)
            if activate {
                self.currentGroup = group
            }
            try PersistenceController.shared.container.viewContext.save()
            return group.objectID
        }
    }
    
    @MainActor
    func createNewFile(active: Bool = true) throws {
        guard let currentGroup else { throw AppError.stateError(.currentGroupNil) }
        let file = try PersistenceController.shared.createFile(in: currentGroup)
        if active {
            currentFile = file
        }
        PersistenceController.shared.save()
    }
    
    func updateCurrentFileData(data: Data) {
        guard !shouldIgnoreUpdate, currentFile?.inTrash != true else {
            return
        }
//        logger.info("\(#function) data: \(data)")
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
//        logger.info("\(#function) file: \(String(describing: excalidrawFile))")
        if let file = self.currentFile {
            let didUpdateFile = didUpdateFile
            let id = file.objectID
            let bgContext = PersistenceController.shared.container.newBackgroundContext()
            
            Task.detached {
                do {
                    try await bgContext.perform {
                        guard let file = bgContext.object(with: id) as? File else { return }
                        try file.updateElements(
                            with: JSONEncoder().encode(excalidrawFile),
                            newCheckpoint: !didUpdateFile
                        )
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
    
    
    func importFile(_ url: URL, toDefaultGroup: Bool = false) async throws {
        let fileType: UTType = {
            let lastPathComponent = url.lastPathComponent
            
            if lastPathComponent.hasSuffix(".excalidraw.png") {
                return .excalidrawPNG
            } else if lastPathComponent.hasSuffix(".excalidraw.svg") {
                return .excalidrawSVG
            } else {
                return UTType(filenameExtension: url.pathExtension) ?? .excalidrawFile
            }
        }()
        let data: Data
        switch fileType {
            case .excalidrawFile:
                // .uncached fixes the import bug occurs in x86 mac OS
                data = try Data(contentsOf: url, options: .uncached)
            case .excalidrawPNG:
                // .uncached fixes the import bug occurs in x86 mac OS
                let fileData = try Data(contentsOf: url, options: .uncached)
                if let excalidrawFile = ExcalidrawPNGDecoder().decode(from: fileData) {
                    data = try JSONEncoder().encode(excalidrawFile)
                } else {
                    data = try Data(contentsOf: url, options: .uncached)
                }
            case .excalidrawSVG:
                // .uncached fixes the import bug occurs in x86 mac OS
                let fileData = try Data(contentsOf: url, options: .uncached)
                if let excalidrawFile = ExcalidrawSVGDecoder().decode(from: fileData) {
                    data = try JSONEncoder().encode(excalidrawFile)
                } else {
                    data = try Data(contentsOf: url, options: .uncached)
                }
            default:
                throw AppError.fileError(.invalidURL)
        }

        _ = try ExcalidrawFile(data: data)
        
        var targetGroup: Group?
        if toDefaultGroup {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
            fetchRequest.fetchLimit = 1
            try await viewContext.perform {
                let result = (try viewContext.fetch(fetchRequest).first) as Group?
                targetGroup = result
            }
        }
        
        let group = targetGroup
        try await MainActor.run {
            guard let currentGroup = group ?? self.currentGroup else { throw AppError.stateError(.currentGroupNil) }
            let file = try PersistenceController.shared.createFile(in: currentGroup)
            switch fileType {
                case .excalidrawFile:
                    file.name = url.deletingPathExtension().lastPathComponent
                case .excalidrawPNG, .excalidrawSVG:
                    let lastPathComponent = url.deletingPathExtension().lastPathComponent
                    if let index = lastPathComponent.lastIndex(of: ".") {
                        file.name = String(lastPathComponent.prefix(upTo: index))
                    } else {
                        file.name = lastPathComponent
                    }
                default:
                    break
            }
            
            file.content = data
            PersistenceController.shared.save()
            self.currentFile = file
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
    }
    
    @discardableResult
    private func importGroupFiles(url: URL, viewContext: NSManagedObjectContext) throws -> NSManagedObjectID {
        let groupName = url.lastPathComponent
        // create group
        let group = Group(name: groupName, context: viewContext)
        let urls = try flatFiles(in: url).filter{
            $0.pathExtension == UTType.excalidrawFile.preferredFilenameExtension
        }
        for url in urls {
            let data = try Data(contentsOf: url, options: .uncached)
            let file = File(name: url.deletingPathExtension().lastPathComponent, context: viewContext)
            file.content = data
            file.group = group
        }
        
        return group.objectID
    }
    
    func renameFile(_ file: File, newName: String) {
        file.name = newName
        PersistenceController.shared.save()
    }
    
    func renameGroup(_ group: Group, newName: String) {
        group.name = newName
        PersistenceController.shared.save()
    }
    
    func moveFile(_ file: File, to group: Group) {
        file.group = group
        if file == currentFile {
            currentGroup = group
            currentFile = file
        }
        PersistenceController.shared.save()
    }
    
    @MainActor
    func duplicateFile(_ file: File) {
        let newFile = PersistenceController.shared.duplicateFile(file: file)
        currentFile = newFile
        PersistenceController.shared.save()
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
}
