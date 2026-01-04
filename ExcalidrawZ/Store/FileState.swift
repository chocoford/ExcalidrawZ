//
//  FileState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import Logging
import UniformTypeIdentifiers
@preconcurrency import CoreData
import ChocofordEssentials


final class FileState: ObservableObject {
    let logger = Logger(label: "FileState")
    
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
                    // file.objectID.description
                    file.id?.uuidString ?? UUID().uuidString
                case .localFile(let url):
                    url.absoluteString
                case .temporaryFile(let url):
                    url.absoluteString
                case .collaborationFile(let collaborationFile):
                    // collaborationFile.objectID.description
                    collaborationFile.id?.uuidString ?? UUID().uuidString
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
            if let currentActiveFileID = self.currentActiveFile?.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NotificationCenter.default.post(
                        name: .filePreviewShouldRefresh,
                        object: currentActiveFileID
                    )
                }
            }
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
            if let currentActiveFile {
                didUpdateFileState[currentActiveFile] = false
            }
            if let newValue {
                didUpdateFileState[newValue] = false
            }
        }
    }
    
    /// Set active file with automatic iCloud download handling
    ///
    /// This method checks if the file needs to be downloaded from iCloud
    /// and waits for the download to complete before setting it as active.
    ///
    /// Use this method instead of directly setting `currentActiveFile` when
    /// the file might need to be downloaded from iCloud.
    ///
    /// - Parameter file: The file to activate
    /// - Throws: FileAccessError if download fails
    @MainActor
    func setActiveFile(_ file: ActiveFile?) {
        guard let file else {
            self.currentActiveFile = nil
            return
        }
        // Check if file needs download
        switch file {
            case .localFile(let url):
                // Check iCloud status
                let statusBox = FileStatusService.shared.statusBox(for: file)
                let status = statusBox.status

                logger.debug("Setting active file: \(url.lastPathComponent), status: \(status)")

                // Download if needed (notDownloaded, outdated, or currently downloading)
                if status.iCloudStatus == .notDownloaded || status.iCloudStatus == .outdated || status.iCloudStatus.isInProgress {
                    logger.info("Downloading file: \(url.lastPathComponent)")
                    Task {
                        do {
                            try await FileSyncCoordinator.shared.downloadFile(url)
                        } catch {
                            print(error)
                        }
                    }
                }
                self.currentActiveFile = file
            case .file, .temporaryFile, .collaborationFile:
                // Database files, temporary files, and collaboration files don't need download check
                self.currentActiveFile = file
        }
    }
    
    @Published var selectedGroups: Set<NSManagedObjectID> = []
    // @Published var selectedLocalFolders: Set<LocalFolder> = []
    
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
    var didUpdateFileState: [ActiveFile : Bool] = [:]
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
                    self.expandToGroup(group.objectID)
                }
            }
        }
        
        return groupID
    }
    
    @discardableResult
    func createNewFile(
        active: Bool = true,
        in groupID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext
    ) async throws -> NSManagedObjectID {
        guard let targetGroupID = groupID ?? {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup.objectID
            }
            return nil
        }() else { throw AppError.stateError(.currentGroupNil) }
        
        let templateData = ExcalidrawFile().content!
        
        // Create file through repository (creates entity and saves to iCloud Drive)
        let fileID = try await PersistenceController.shared.fileRepository.createFile(
            name: String(localizable: .newFileNamePlaceholder),
            content: templateData,
            groupObjectID: targetGroupID
        )
        
        if active {
            await MainActor.run {
                if let file = context.object(with: fileID) as? File {
                    self.setActiveFile(.file(file))
                    if let group = file.group {
                        self.currentActiveGroup = .group(group)
                        self.expandToGroup(group.objectID)
                    }
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
        let didUpdateFile = didUpdateFileState[.file(file)] ?? false
        let id = file.objectID
        self.didUpdateFileState[.file(file)] = true
        Task.detached {
            do {
                guard let content = excalidrawFile.content else { return }
                
                // Step 1: Sync media items from ExcalidrawFile (creates new ones and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.syncMediaItemsForFile(
                    excalidrawFile: excalidrawFile,
                    fileObjectID: id
                )
                
                // Step 2: Update file elements through repository
                try await PersistenceController.shared.fileRepository.updateElements(
                    fileObjectID: id,
                    fileData: content,
                    newCheckpoint: !didUpdateFile
                )
                self.logger.info("updateFile done...")
                await MainActor.run {
                    // already throttled
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
        
        while FileManager.default.fileExists(
            at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
        ) {
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
                self.setActiveFile(.localFile(fileURL))
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
        try await context.perform {
            let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "url = %@", url as NSURL)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocalFileCheckpoint.updatedAt, ascending: false)]
            let localFileCheckpoints = try context.fetch(fetchRequest)
            
            if didUpdateFile, let firstCheckpoint = localFileCheckpoints.first {
                firstCheckpoint.updatedAt = Date()
                firstCheckpoint.content = excalidrawFile.content
            } else {
                let localFileCheckpoint = LocalFileCheckpoint(context: context)
                localFileCheckpoint.url = url
                localFileCheckpoint.updatedAt = Date()
                localFileCheckpoint.content = excalidrawFile.content
                
                context.insert(localFileCheckpoint)
                
                if localFileCheckpoints.count > 50, let last = localFileCheckpoints.last {
                    context.delete(last)
                }
            }
            
        }
        
        await MainActor.run {
            self.didUpdateFile = true
        }
    }
    
    
    func updateCurrentCollaborationFile(with excalidrawFile: ExcalidrawFile) {
        guard !shouldIgnoreUpdate else { return }
        let didUpdateFile = didUpdateFile
        let id = excalidrawFile.id
        let context = PersistenceController.shared.newTaskContext()
        
        Task.detached {
            do {
                // Step 1: Get collaboration file objectID and update roomID
                let fileObjectID = try await context.perform {
                    let fetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                    fetchRequest.predicate = NSPredicate(format: "id = %@", id as CVarArg)
                    
                    guard let file = try context.fetch(fetchRequest).first else {
                        throw AppError.fileError(.contentNotAvailable(filename: excalidrawFile.name ?? String(localizable: .generalUnknown)))
                    }
                    
                    // Update roomID
                    file.roomID = excalidrawFile.roomID
                    
                    try context.save()
                    
                    return file.objectID
                }
                
                // Sync media items from ExcalidrawFile (creates new ones and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.syncMediaItemsForCollaborationFile(
                    excalidrawFile: excalidrawFile,
                    collaborationFileObjectID: fileObjectID
                )
                
                // Step 2: Update content using repository (saves to iCloud Drive and creates checkpoint)
                guard let content = excalidrawFile.content else { return }
                try await PersistenceController.shared.collaborationFileRepository.updateElements(
                    collaborationFileObjectID: fileObjectID,
                    content: content,
                    newCheckpoint: !didUpdateFile
                )
                
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
        let context = PersistenceController.shared.newTaskContext()
        let currentGroup: Group? = {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup
            }
            return nil
        }()
        let currentGroupID = currentGroup?.objectID
        
        let fileContentData = try excalidrawFile.contentWithoutFiles()
        
        // Get target group ID
        let targetGroupID = try await context.perform {
            var targetGroup: Group?
            
            if targetGroupType == .default || currentGroupID == nil {
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
            
            return group.objectID
        }
        
        // Create file through repository (creates entity and saves to iCloud Drive)
        let fileID = try await PersistenceController.shared.fileRepository.createFile(
            name: excalidrawFile.name ?? "Untitled",
            content: fileContentData,
            groupObjectID: targetGroupID
        )
        
        // Get media items that need to be imported
        let mediaItemsNeedImport = try await context.perform {
            let mediaItems = try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
            return excalidrawFile.files.values.filter { item in
                !mediaItems.contains(where: { $0.id == item.id })
            }
        }
        
        // Create media items through repository (creates entities and saves to iCloud Drive)
        if !mediaItemsNeedImport.isEmpty {
            _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                resources: Array(mediaItemsNeedImport),
                fileObjectID: fileID
            )
        }
        
        try? await self.excalidrawWebCoordinator?.insertMediaFiles(Array(mediaItemsNeedImport))
        await MainActor.run {
            if let file = context.object(with: fileID) as? File {
                self.setActiveFile(.file(file))
                if let group = file.group {
                    self.currentActiveGroup = .group(group)
                    self.expandToGroup(group.objectID)
                }
            }
        }
    }
    
    /// Different handle logics according to different combinations of urls.
    /// * only files: Import to current group ?? default group..
    /// * 1 folder:
    ///     * if has subfolders: Create groups by folders & Group remains files to `Ungrouped`
    ///     * if only files: import all files to one group with the same name of the ancestor folder.
    /// * multiple folders: Create groups by folders
    /// * folders & files: Create groups by folders & Group remains files to `Ungrouped`
    func importFiles(_ urls: [URL]) async throws {
        let context = PersistenceController.shared.container.viewContext
        
        let currentGroup: Group? = if case .group(let currentGroup) = self.currentActiveGroup {
            currentGroup
        } else {
            nil
        }
        let crrentGroupID = currentGroup?.objectID
        
        if urls.count == 1, let url = urls.first {
            guard url.startAccessingSecurityScopedResource() else {
                throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            if FileManager.default.isDirectory(url) {
                // select a directory
                try await self.importGroup(
                    url: url,
                    parentGroupID: crrentGroupID,
                    context: context
                )
            } else {
                // select only one excalidraw file
                try await self.importFile(url)
            }
        } else if urls.count > 1 {
            // select multiple files or folders
            // folders will be created as group, files will be imported to `default` group.
            let context = PersistenceController.shared.newTaskContext()
            // Prepare file data outside context.perform
            var fileDataPairs: [(URL, Data)] = []
            for fileURL in urls.filter({!FileManager.default.isDirectory($0)}) {
                guard fileURL.startAccessingSecurityScopedResource() else {
                    throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                }
                let data = try Data(contentsOf: fileURL, options: .uncached)
                fileURL.stopAccessingSecurityScopedResource()
                fileDataPairs.append((fileURL, data))
            }
            
            // Get target group ID
            let targetGroupID = try await context.perform {
                let fetchRequest = NSFetchRequest<Group>()
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                var group: Group?
                let currentGroup: Group? = if let crrentGroupID {
                    context.object(with: crrentGroupID) as? Group
                } else {
                    nil
                }
                if let currentGroup {
                    group = currentGroup
                } else if let defaultGroup = try context.fetch(fetchRequest).first {
                    group = defaultGroup
                }
                guard let group else { throw AppError.stateError(.currentGroupNil) }
                
                return group.objectID
            }
            
            // Create files through repository (creates entities and saves to iCloud Drive)
            for (fileURL, data) in fileDataPairs {
                _ = try await PersistenceController.shared.fileRepository.createFile(
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    content: data,
                    groupObjectID: targetGroupID
                )
            }
            
            
            // folders
            for folderURL in urls.filter({FileManager.default.isDirectory($0)}) {
                guard folderURL.startAccessingSecurityScopedResource() else {
                    throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                try await self.importGroup(
                    url: folderURL,
                    parentGroupID: currentGroup?.objectID,
                    context: context
                )
            }
            
        }
    }
    
    /// Import a folder as a group.
    private func importGroup(
        url: URL,
        parentGroupID: NSManagedObjectID?,
        context: NSManagedObjectContext
    ) async throws {
        let groupName = url.lastPathComponent
        
        // create group
        let group = try await context.perform {
            let group: Group = Group(name: groupName, context: context)
            context.insert(group)
            let parentGroup: Group? = if let parentGroupID {
                context.object(with: parentGroupID) as? Group
            } else {
                nil
            }
            group.parent = parentGroup
            try context.save()
            return group
        }
        let groupID = group.objectID
        
        // contents
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: []
        )
        
        // Import medias
        let allMediaItems = try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        var insertedMediaID = Set<String>()
        
        // files
        for fileURL in urls where fileURL.pathExtension == UTType.excalidrawFile.preferredFilenameExtension  {
            let excalidrawFile = try ExcalidrawFile(contentsOf: fileURL)
            let data = try Data(contentsOf: fileURL, options: .uncached)
            
            // Create file through repository (creates entity and saves to iCloud Drive)
            let fileID = try await PersistenceController.shared.fileRepository.createFile(
                name: fileURL.deletingPathExtension().lastPathComponent,
                content: data,
                groupObjectID: groupID
            )
            
            // Import medias
            let mediasToImport = excalidrawFile.files.values.filter { item in
                !insertedMediaID.contains(item.id) &&
                !allMediaItems.contains(where: {$0.id == item.id})
            }
            
            if !mediasToImport.isEmpty {
                // Create media items through repository (creates entities and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                    resources: Array(mediasToImport),
                    fileObjectID: fileID
                )
                
                // Mark as inserted to avoid duplicates in next iterations
                mediasToImport.forEach { insertedMediaID.insert($0.id) }
                
                Task {
                    try? await self.excalidrawWebCoordinator?.insertMediaFiles(Array(mediasToImport))
                }
            }
        }
        
        // folders
        for folderURL in urls where FileManager.default.isDirectory(folderURL) {
            try await self.importGroup(
                url: folderURL,
                parentGroupID: group.objectID,
                context: context
            )
        }
        
        try context.save()
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
    func duplicateFile(_ file: File, context: NSManagedObjectContext) async throws -> NSManagedObjectID {
        let fileID = file.objectID
        let fileName = file.name
        let groupID = file.group?.objectID
        
        // Load file content from iCloud Drive
        let content = try await file.loadContent()
        
        // Get file's group ID
        guard let groupID else {
            throw AppError.stateError(.currentGroupNil)
        }
        
        // Create duplicated file through repository (creates entity and saves to iCloud Drive)
        let newFileID = try await PersistenceController.shared.fileRepository.createFile(
            name: fileName ?? "Untitled",
            content: content,
            groupObjectID: groupID
        )
        
        // Copy media items if any
        let mediaItemsToCopy: [MediaItem] = await context.perform {
            guard let file = context.object(with: fileID) as? File else { return [] }
            let medias = file.medias?.allObjects as? [MediaItem] ?? []
            return medias
        }
        
        if !mediaItemsToCopy.isEmpty {
            // Load media resources
            var resources: [ExcalidrawFile.ResourceFile] = []
            for mediaItem in mediaItemsToCopy {
                if let resource = try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem) {
                    resources.append(resource)
                }
            }
            
            // Create media items for the new file
            if !resources.isEmpty {
                _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                    resources: resources,
                    fileObjectID: newFileID
                )
            }
        }
        
        return newFileID
    }
    
    func recoverFile(fileID: NSManagedObjectID, context: NSManagedObjectContext) async throws {
        let file: File? = try await context.perform {
            guard let file = context.object(with: fileID) as? File else { return nil }
            guard file.inTrash else { return nil }
            file.inTrash = false
            
            if let groupID = file.group?.objectID {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "id == %@", groupID as CVarArg)
                fetchRequest.fetchLimit = 1
                if try context.fetch(fetchRequest).isEmpty {
                    let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context)
                    file.group = defaultGroup
                }
            } else {
                let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context)
                file.group = defaultGroup
            }
            
            try context.save()
            
            return file
        }
        
        if let file {
            let fileID = file.objectID
            
            await MainActor.run {
                guard let file = context.object(with: fileID) as? File else { return }
                if self.currentActiveFile == .file(file) {
                    if let group = file.group {
                        self.currentActiveGroup = .group(group)
                        self.expandToGroup(group.objectID)
                    }
                }
            }
        }
    }
    
    func mergeDefaultGroupAndTrashIfNeeded(context: NSManagedObjectContext) async throws {
        try await context.perform {
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
        }
    }
    
    public func expandToGroup(_ groupID: NSManagedObjectID, expandSelf: Bool = true) {
        let context = PersistenceController.shared.newTaskContext()
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
        let (_, group): (File?, Group?) = try await viewContext.perform {
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
            self.expandToGroup(group.objectID)
            //            if let file {
            //                self.setActiveFile(.file(file))
            //            }
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
