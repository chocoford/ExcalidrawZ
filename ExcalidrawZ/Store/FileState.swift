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
import ChocofordEssentials

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
            currentLocalFolder = nil
            currentLocalFile = nil
            isTemporaryGroupSelected = false
            currentTemporaryFile = nil
            isInCollaborationSpace = false
            resetSelections()
        }
    }
    
    @Published var currentFile: File? {
        didSet {
            print("freeze watchUpdate: \(Date.now.formatted(date: .omitted, time: .complete))")
            shouldIgnoreUpdate = true
            recoverWatchUpdate()
            currentFilePublisherCancellables.forEach{$0.cancel()}
            resetSelections()
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
                currentLocalFolder = nil
                currentLocalFile = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
                isInCollaborationSpace = false
                // selectedFiles = [currentFile]
            }
        }
    }
    @Published var selectedFiles: Set<File> = []
    @Published var selectedStartFile: File?
    
    @Published var currentLocalFolder: LocalFolder? {
        didSet {
            resetSelections()

            if currentLocalFolder != nil {
                currentFile = nil
                currentGroup = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
                isInCollaborationSpace = false
            }
        }
    }

    @Published var currentLocalFile: URL? {
        didSet {
            resetSelections()

            if currentLocalFile != nil {
                currentFile = nil
                currentGroup = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
                isInCollaborationSpace = false
                // selectedLocalFiles = [currentLocalFile]
            }
        }
    }
    @Published var currentLocalFileBookmarkData: Data? {
        didSet {
            if currentLocalFileBookmarkData != nil {
                currentFile = nil
                currentGroup = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
                isInCollaborationSpace = false
            }
        }
    }
    @Published var selectedLocalFiles: Set<URL> = []
    @Published var selectedStartLocalFile: URL?

    @Published var isTemporaryGroupSelected = false {
        didSet {
            resetSelections()
            if isTemporaryGroupSelected {
                currentFile = nil
                currentGroup = nil
                currentLocalFolder = nil
                currentLocalFile = nil
                isInCollaborationSpace = false
            }
        }
    }
    @Published var temporaryFiles: [URL] = []
    @Published var currentTemporaryFile: URL? {
        didSet {
            resetSelections()
            if currentTemporaryFile != nil {
                currentFile = nil
                currentGroup = nil
                currentLocalFolder = nil
                currentLocalFile = nil
                // selectedTemporaryFiles = [currentTemporaryFile]
            }
        }
    }
    @Published var selectedTemporaryFiles: Set<URL> = []
    @Published var selectedStartTemporaryFile: URL?
    // Collab
    @Published var isInCollaborationSpace = false {
        didSet {
            if isInCollaborationSpace {
                currentFile = nil
                currentGroup = nil
                currentLocalFolder = nil
                currentLocalFile = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
            }
        }
    }
    /// Files that is currently under collaboration.
    @Published var collaboratingFiles: [CollaborationFile] = []
    @Published var collaboratingFilesState: [CollaborationFile : ExcalidrawView.LoadingState] = [:]
    @Published var collaborators: [CollaborationFile : [Collaborator]] = [:]
    enum CollborationRoute: Hashable {
        case home
        case room(CollaborationFile)
        
        var room: CollaborationFile? {
            switch self {
                case .home:
                    nil
                case .room(let collaborationFile):
                    collaborationFile
            }
        }
    }
    @Published var currentCollaborationFile: CollborationRoute? {
        didSet {
            if case .room(let file) = currentCollaborationFile {
                currentFile = nil
                currentGroup = nil
                currentLocalFolder = nil
                currentLocalFile = nil
                isTemporaryGroupSelected = false
                currentTemporaryFile = nil
                isInCollaborationSpace = true
                if !collaboratingFiles.contains(where: {$0 == file}) {
                    collaboratingFiles.append(file)
                }
            }
        }
    }
    var currentCollaborators: [Collaborator] {
        if case .room(let file) = currentCollaborationFile {
            collaborators[file] ?? []
        } else {
            []
        }
    }
    
    @AppStorage("ExcalidrawFileSortField") var sortField: ExcalidrawFileSortField = .updatedAt
    
    var hasAnyActiveGroup: Bool {
        currentGroup != nil || currentLocalFolder != nil || isTemporaryGroupSelected || isInCollaborationSpace
    }
    var hasAnyActiveFile: Bool {
        if currentGroup != nil && currentFile != nil ||
            currentLocalFolder != nil && currentLocalFile != nil ||
            isTemporaryGroupSelected && currentTemporaryFile != nil {
            return true
        } else if case .room = currentCollaborationFile, isInCollaborationSpace {
            return true
        }
        return false
    }

    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    var excalidrawCollaborationWebCoordinator: ExcalidrawView.Coordinator?
    
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
    func createNewGroup(
        name: String,
        activate: Bool = true,
        parentGroupID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext
    ) async throws -> NSManagedObjectID {
        try await context.perform {
            let group = Group(name: name, context: context)
            
            if let parentGroupID,
               let parent = context.object(with: parentGroupID) as? Group {
                group.parent = parent
            }
            try context.save()
            if activate {
                Task {
                    await MainActor.run {
                        self.currentGroup = group
                    }
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
    
    func createNewLocalFile(active: Bool = true, folderURL scopedURL: URL) async throws {
        guard let data = ExcalidrawFile().content else { return }
        var newFileName = "Untitled"
        
        while FileManager.default.fileExists(at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)) {
            let components = newFileName.components(separatedBy: "-")
            if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                newFileName = "\(components[0])-\(index+1)"
            } else {
                newFileName = "\(newFileName)-1"
            }
        }
        
        let fileCoordinator = NSFileCoordinator()
        
        let fileURL = scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
        
        try await withCheckedThrowingContinuation { continuation in
            fileCoordinator.coordinate(
                writingItemAt: fileURL,
                options: .forReplacing,
                error: nil
            ) { newURL in
                // 文件操作
                do {
                    try data.write(to: newURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        if active {
            await MainActor.run {
                self.currentLocalFile = fileURL
            }
        }
    }
    
    /// Remember to call `startAccessingSecurityScopedResource` before calling this function.
    func updateLocalFile(to url: URL, with excalidrawFile: ExcalidrawFile, context: NSManagedObjectContext) async throws {
        guard !shouldIgnoreUpdate/*, let fileURL = self.currentLocalFile*/ else { return }
        let didUpdateFile = didUpdateFile
        var excalidrawFile = excalidrawFile
        try excalidrawFile.updateContentFilesFromFiles()
        try JSONEncoder().encode(excalidrawFile).write(to: url)
        let bgContext = context // PersistenceController.shared.container.newBackgroundContext()
        try await bgContext.perform {
            let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "url = %@", url as NSURL)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocalFileCheckpoint.updatedAt, ascending: false)]
            let localFileCheckpoints = try bgContext.fetch(fetchRequest)
            
            if didUpdateFile, let firstCheckpoint = localFileCheckpoints.first {
                firstCheckpoint.updatedAt = Date()
                firstCheckpoint.content = excalidrawFile.content
            } else {
                let localFileCheckpoint = LocalFileCheckpoint(context: bgContext)
                localFileCheckpoint.url = url
                localFileCheckpoint.updatedAt = Date()
                localFileCheckpoint.content = excalidrawFile.content
                
                bgContext.insert(localFileCheckpoint)
                
                if localFileCheckpoints.count > 50, let last = localFileCheckpoints.last {
                    bgContext.delete(last)
                }
            }
            
        }
        
        await MainActor.run {
            self.didUpdateFile = true
        }
    }
    
    
    func updateCurrentCollaborationFile(with excalidrawFile: ExcalidrawFile) {
        guard !shouldIgnoreUpdate else {
            return
        }
        let didUpdateFile = didUpdateFile
        let id = excalidrawFile.id
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        
        Task.detached {
            do {
                try await bgContext.perform {
                    let fetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                    fetchRequest.predicate = NSPredicate(format: "id = %@", id as CVarArg)
                    
                    
                    guard let file = try bgContext.fetch(fetchRequest).first,
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
                        mediaItem.collaborationFile = file
                        bgContext.insert(mediaItem)
                    }
                    
                    // update roomID
                    file.roomID = excalidrawFile.roomID
                    
                    try bgContext.save()
                }
                await MainActor.run {
                    self.didUpdateFile = true
                }
            } catch {
                print(error)
            }
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

             Task {
                 try? await self.excalidrawWebCoordinator?.insertMediaFiles(mediaItemsNeedImport)
                 await MainActor.run {
                     self.currentFile = file
                 }
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
            guard url.startAccessingSecurityScopedResource() else {
                throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
            }
            defer { url.stopAccessingSecurityScopedResource() }
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
                    guard folderURL.startAccessingSecurityScopedResource() else {
                        throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                    }
                    defer { folderURL.stopAccessingSecurityScopedResource() }
                    try self.importGroupFiles(url: folderURL, viewContext: viewContext)
                }
                // only files
                for fileURL in urls.filter({!FileManager.default.isDirectory($0)}) {
                    guard fileURL.startAccessingSecurityScopedResource() else {
                        throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                    }
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    
                    let data = try Data(contentsOf: fileURL, options: .uncached)
                    let file = File(name: fileURL.deletingPathExtension().lastPathComponent, context: viewContext)
                    file.content = data
                    file.group = group
                }
                try viewContext.save()
                
                groupID = group.objectID
            }
        }
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
    
    
    func renameFile(_ fileID: NSManagedObjectID, context: NSManagedObjectContext, newName: String) {
        context.perform {
            guard let file = context.object(with: fileID) as? File else { return }
            file.name = newName
            try? context.save()
            self.objectWillChange.send()
        }
    }
    
    func renameGroup(_ group: Group, newName: String) {
        group.name = newName
        PersistenceController.shared.save()
        self.objectWillChange.send()
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

    func mergeDefaultGroupAndTrashIfNeeded(context: NSManagedObjectContext) async throws {
        print("mergeDefaultGroupAndTrashIfNeeded...")
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
                
                Task {
                    await MainActor.run {
                        self.currentGroup = theEearlisetGroup
                    }
                }
            }
            
            let trashGroups = groups.filter({$0.groupType == .trash})
            trashGroups.dropFirst().forEach { trash in
                context.delete(trash)
            }
            try context.save()
        }
    }
    
    public func expandToGroup(_ groupID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            await context.perform {
                guard case let targetGroup as any ExcalidrawFileGroupRepresentable = context.object(with: groupID) else { return }
                
                var groupIDs: [NSManagedObjectID] = []
                // get groupIDs
                do {
                    var targetGroupID: NSManagedObjectID? = groupID
                    var parentGroup: (any ExcalidrawFileGroupRepresentable)? = targetGroup
                    while true {
                        guard let parentGroupID = (parentGroup?.getParent() as? (any ExcalidrawFileGroupRepresentable))?.objectID else {
                            break
                        }
                        parentGroup = context.object(with: parentGroupID) as? (any ExcalidrawFileGroupRepresentable)
                        targetGroupID = parentGroup?.objectID
                        if let targetGroupID {
                            groupIDs.insert(targetGroupID, at: 0)
                        }
                    }
                }
                Task { [groupIDs] in
                    for groupId in groupIDs {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .shouldExpandGroup,
                                object: groupId
                            )
                        }
                        try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                    }
                }
            }
        }
    }
    
    @MainActor
    public func setToDefaultGroup() async throws {
        let viewContext = PersistenceController.shared.container.viewContext
        try await viewContext.perform {
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type = %@", "default")
            if let defaultGroup = try viewContext.fetch(fetchRequest).first {
                self.currentGroup = defaultGroup
                
                let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
                fileFetchRequest.predicate = NSPredicate(format: "group = %@ AND inTrash = false", defaultGroup)
                fileFetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \File.updatedAt, ascending: false)
                ]
                self.currentFile = try viewContext.fetch(fileFetchRequest).first
            }
        }
    }
    
    
    public func resetSelections() {
        self.selectedFiles = []
        self.selectedStartFile = nil
        self.selectedLocalFiles = []
        self.selectedStartLocalFile = nil
        self.selectedTemporaryFiles = []
    }
}
