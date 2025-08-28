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
@preconcurrency import CoreData
import ChocofordEssentials


final class FileState: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FileState")
    
    var stateUpdateQueue: DispatchQueue = DispatchQueue(label: "StateUpdateQueue")
    
    var currentGroupPublisherCancellables: [AnyCancellable] = []
    var currentFilePublisherCancellables: [AnyCancellable] = []
    
    enum ActiveGroup: Identifiable, Equatable {
        case group(Group)
        case localFolder(LocalFolder)
        case temporary
        case collaboration
        
        var id: String {
            switch self {
                case .group(let group):
                    (group.id ?? UUID()).uuidString
                case .localFolder(let folder):
                    folder.filePath ?? UUID().uuidString
                case .temporary:
                    "temporary"
                case .collaboration:
                    "collaboration"
            }
        }
    }
  
    @Published var currentActiveGroup: ActiveGroup? {
        didSet {
            currentGroupPublisherCancellables.forEach {$0.cancel()}
            guard let currentActiveGroup else { return }
            if case .group(let group) = currentActiveGroup {
                currentGroupPublisherCancellables = [
                    group.publisher(for: \.name).sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.objectWillChange.send()
                        }
                    }
                ]
            }
            DispatchQueue.main.async {
                self.resetSelections()
            }
        }
    }

    enum ActiveFile: Identifiable, Hashable {
        case file(File)
        case localFile(URL)
        case temporaryFile(URL)
        case collaborationFile(CollaborationFile)
        
        var id: String {
            switch self {
                case .file(let file):
                    file.objectID.description
                case .localFile(let url):
                    url.absoluteString
                case .temporaryFile(let url):
                    url.absoluteString
                case .collaborationFile(let collaborationFile):
                    collaborationFile.objectID.description 
            }
        }
        
        var name: String? {
            switch self {
                case .file(let file):
                    file.name
                case .localFile(let url):
                    url.deletingPathExtension().lastPathComponent
                case .temporaryFile(let url):
                    url.deletingPathExtension().lastPathComponent
                case .collaborationFile(let file):
                    file.name
            }
        }
        
        var updatedAt: Date? {
            switch self {
                case .file(let file):
                    file.updatedAt
                case .localFile(let url):
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                case .temporaryFile(let url):
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                case .collaborationFile(let file):
                    file.updatedAt
            }
        }
    }
    
    @Published var activeFileIndex: Int? = 0
    @Published var activeFiles: [ActiveFile?] = [nil] {
        willSet {
            guard let activeFileIndex else { return }
            self.activeFileIndex = min(newValue.endIndex - 1, activeFileIndex)
        }
        didSet {
            
        }
    }
    var currentActiveFile: ActiveFile? {
        get {
            if let activeFileIndex, activeFileIndex >= 0, activeFileIndex < activeFiles.count {
                return activeFiles[activeFileIndex]
            }
            return nil
        }
        
        set {
            if let activeFileIndex,
               activeFileIndex < activeFiles.count {
                if let newValue {
                    activeFiles[activeFileIndex] = newValue
                } else if activeFileIndex > 0 {
                    activeFiles.remove(at: activeFileIndex)
                } else {
                    activeFiles[activeFileIndex] = nil
                }
            }
            
            shouldIgnoreUpdate = true
            recoverWatchUpdate()
            currentFilePublisherCancellables.forEach{$0.cancel()}
            resetSelections()
        }
    }
    
    @Published var selectedFiles: Set<File> = []
    @Published var selectedStartFile: File?
    
    @Published var selectedLocalFiles: Set<URL> = []
    @Published var selectedStartLocalFile: URL?

    @Published var temporaryFiles: [URL] = []
    
    @Published var selectedTemporaryFiles: Set<URL> = []
    @Published var selectedStartTemporaryFile: URL?
    
    // Collab
    
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = currentActiveFile {
            return true
        }
        if case .collaboration = currentActiveGroup {
            return true
        }
        return false
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
    
    var currentCollaborators: [Collaborator] {
        if case .collaborationFile(let file) = currentActiveFile {
            collaborators[file] ?? []
        } else {
            []
        }
    }
    
    @AppStorage("ExcalidrawFileSortField") var sortField: ExcalidrawFileSortField = .updatedAt
    
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    var excalidrawCollaborationWebCoordinator: ExcalidrawView.Coordinator?
    
    var shouldIgnoreUpdate = true
    /// Indicate the file is being updated after being set as current file.
    var didUpdateFile = false
    var didUpdateFileState: [NSManagedObjectID : Bool] = [:]
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
        context: NSManagedObjectContext,
        animation: Animation? = nil,
    ) async throws -> NSManagedObjectID {
        let groupID = try await context.perform {
            let group = withAnimation(animation) {
                
                let group = Group(name: name, context: context)
                
                if let parentGroupID,
                   let parent = context.object(with: parentGroupID) as? Group {
                    group.parent = parent
                }
                
                context.insert(group)
                return group
            }
            
            try context.save()
            
            return group.objectID
        }
        
        if activate {
            await MainActor.run {
                if let group = context.object(with: groupID) as? Group {
                    self.currentActiveGroup = .group(group)
                }
            }
        }
        
        return groupID
    }
    
    @discardableResult
    func createNewFile(
        active: Bool = true,
        in groupID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext,
        animation: Animation? = nil,
    ) async throws -> NSManagedObjectID {
        guard let targetGroupID = groupID ?? {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup.objectID
            }
            return nil
        }() else { throw AppError.stateError(.currentGroupNil) }
        
        let fileID = try await context.perform {
            
            let file = File(name: String(localizable: .newFileNamePlaceholder), context: context)
            
            guard let group = context.object(with: targetGroupID) as? Group else {
                throw AppError.groupError(.notFound(targetGroupID.description))
            }
            file.group = group
            
            guard let templateURL = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else {
                throw AppError.fileError(.notFound)
            }
            file.content = try Data(contentsOf: templateURL)
            
            withAnimation(animation) {
                context.insert(file)
            }
            
            try context.save()
            
            return file.objectID
        }
        
        if active {
            await MainActor.run {
                if let file = context.object(with: fileID) as? File {
                    self.currentActiveFile = .file(file)
                }
            }
        }
        
        return fileID
    }

    func updateCurrentFile(with excalidrawFile: ExcalidrawFile) {
        if case .file(let file) = self.currentActiveFile {
            updateFile(file, with: excalidrawFile)
        }
    }
    
    func updateFile(_ file: File, with excalidrawFile: ExcalidrawFile) {
        guard !shouldIgnoreUpdate, !file.inTrash else { return }
        let didUpdateFile = didUpdateFileState[file.objectID] ?? false
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
                    // print("Did update file: \(file.name ?? "nil")")
                    // already throttled
                    self.didUpdateFileState[id] = true
                    self.objectWillChange.send()
                }
            } catch {
                print(error)
            }
        }
    }
    
    @discardableResult
    func createNewLocalFile(active: Bool = true, folderURL scopedURL: URL) async throws -> URL? {
        guard let data = ExcalidrawFile().content else { return nil }
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
                self.currentActiveFile = .localFile(fileURL)
            }
        }
        
        return fileURL
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
        let context = PersistenceController.shared.container.viewContext
        let currentGroup: Group? = {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup
            }
            return nil
        }()
        let currentGroupID = currentGroup?.objectID
        
        let (fileID, mediaItemsNeedImport) = try await context.perform {
            var targetGroup: Group?

            if targetGroupType == .default {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                fetchRequest.fetchLimit = 1
                targetGroup = (try context.fetch(fetchRequest).first) as Group?
            } else if case .custom(let id) = targetGroupType, let id {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                fetchRequest.fetchLimit = 1
                targetGroup = (try context.fetch(fetchRequest).first) as Group?
            }
            
            guard let group = targetGroup ?? {
                guard let currentGroupID else { return nil }
                return context.object(with: currentGroupID) as? Group
            }() else { throw AppError.stateError(.currentGroupNil) }
            
            let file = File(name: excalidrawFile.name ?? "Untitled", context: context)
            file.content = try excalidrawFile.contentWithoutFiles()
            file.group = group
            
            let mediaItems = try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
            let mediaItemsNeedImport = excalidrawFile.files.values.filter{ item in !mediaItems.contains(where: {$0.id == item.id})}
            mediaItemsNeedImport.forEach { item in
                let mediaItem = MediaItem(resource: item, context: context)
                mediaItem.file = file
                context.insert(mediaItem)
            }
            
            try context.save()
            
            return (file.objectID, mediaItemsNeedImport)
        }
        
        try? await self.excalidrawWebCoordinator?.insertMediaFiles(mediaItemsNeedImport)
        await MainActor.run {
            if let file = context.object(with: fileID) as? File {
                self.currentActiveFile = .file(file)
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
        guard case .group(let currentGroup) = self.currentActiveGroup else {
            return
        }
        
        let currentGroupID = currentGroup.objectID
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
                if let currentGroup = viewContext.object(with: currentGroupID) as? Group {
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
    
    func recoverFile(fileID: NSManagedObjectID, context: NSManagedObjectContext) async throws {
        let file: File? = try await context.perform {
            guard let file = context.object(with: fileID) as? File else { return nil }
            guard file.inTrash else { return nil }
            file.inTrash = false
            
            if let groupID = file.group?.objectID,
               let group = context.object(with: groupID) as? Group {
//                await MainActor.run {
//                    self.currentActiveGroup = .group(group)
//                }
            } else {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                fetchRequest.fetchLimit = 1
                if let group = try context.fetch(fetchRequest).first {
                    file.group = group
                    
                    
//                    await MainActor.run {
//                        self.currentActiveGroup = .group(group)
//                    }
                }
            }
            
            // self.currentActiveFile = .file(file)
            
            try context.save()
            
            return file
        }
        
        if let file {
            self.currentActiveFile = .file(file)
            if let group = file.group {
                self.currentActiveGroup = .group(group)
            }
        }
    }

    func mergeDefaultGroupAndTrashIfNeeded(context: NSManagedObjectContext) async throws {
        print("mergeDefaultGroupAndTrashIfNeeded...")
        let theEearlisetGroup = try await context.perform {
            let groups = try context.fetch(NSFetchRequest<Group>(entityName: "Group"))
            
            let defaultGroups = groups.filter({$0.groupType == .default})
            var theEearlisetGroup: Group?
            // Merge default groups
            if defaultGroups.count > 1 {
                theEearlisetGroup = defaultGroups.sorted(by: {
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
            }
            
            let trashGroups = groups.filter({$0.groupType == .trash})
            trashGroups.dropFirst().forEach { trash in
                context.delete(trash)
            }
            try context.save()
            
            return theEearlisetGroup
        }
        
        if let theEearlisetGroup {
            self.currentActiveGroup = .group(theEearlisetGroup)
        }
    }
    
    public func expandToGroup(_ groupID: NSManagedObjectID, expandSelf: Bool = true) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            await context.perform {
                guard case let targetGroup as any ExcalidrawGroup = context.object(with: groupID) else { return }
                
                var groupIDs: [NSManagedObjectID] = []
                // get groupIDs
                do {
                    var targetGroupID: NSManagedObjectID? = groupID
                    var parentGroup: (any ExcalidrawGroup)? = targetGroup
                    while true {
                        guard let parentGroupID = (parentGroup?.getParent() as? (any ExcalidrawGroup))?.objectID else {
                            break
                        }
                        parentGroup = context.object(with: parentGroupID) as? (any ExcalidrawGroup)
                        targetGroupID = parentGroup?.objectID
                        if let targetGroupID {
                            groupIDs.insert(targetGroupID, at: 0)
                        }
                    }
                }
                print("expandToGroup: \(groupIDs.map { $0.description })")
                Task { [groupIDs, expandSelf] in
                    for groupId in groupIDs {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .shouldExpandGroup,
                                object: groupId
                            )
                        }
                        try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                    }
                    if expandSelf {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .shouldExpandGroup,
                                object: groupID
                            )
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func setToDefaultGroup() async throws {
        let viewContext = PersistenceController.shared.container.viewContext
        let (file, group): (File?, Group?) = try await viewContext.perform {
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type = %@", "default")
            if let defaultGroup = try viewContext.fetch(fetchRequest).first {
                let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
                fileFetchRequest.predicate = NSPredicate(format: "group = %@ AND inTrash = false", defaultGroup)
                fileFetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \File.updatedAt, ascending: false)
                ]
                return (try viewContext.fetch(fileFetchRequest).first, defaultGroup)
            }
            
            return (nil, nil)
        }
        
        if let group {
            self.currentActiveGroup = .group(group)
            if let file {
                self.currentActiveFile = .file(file)
            }
        }
    }
    
    /// Reset the current file changes listener.
    /// Everytime the current file changes, the listeners will send a `objectWillChange` event.
    private func resetCurrentFileChangesListener() {
        currentFilePublisherCancellables.forEach{$0.cancel()}
        
        if case .file(let currentFile) = self.currentActiveFile {
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
    
    /// Reset all selections to empty.
    public func resetSelections() {
        self.selectedFiles = []
        self.selectedStartFile = nil
        self.selectedLocalFiles = []
        self.selectedStartLocalFile = nil
        self.selectedTemporaryFiles = []
    }
}

