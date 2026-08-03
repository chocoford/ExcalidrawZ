//
//  FileCoverCacheCoordinator.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/23.
//

import CoreData
import Logging
import SwiftUI

extension Notification.Name {
    static let filePreviewDidUpdate = Notification.Name("FilePreviewDidUpdate")
}

@MainActor
final class FileCoverCacheCoordinator: ObservableObject {
    static let shared = FileCoverCacheCoordinator()

    enum Priority: Int {
        case background = 0
        case recently = 5
        case userInitiated = 10
    }

    enum Source {
        case activeFile(FileState.ActiveFile)
        case excalidrawFile(ExcalidrawFile)
        case checkpoint(CheckpointPreviewSource)

        var id: String {
            switch self {
                case .activeFile(let file):
                    file.id
                case .excalidrawFile(let file):
                    file.id
                case .checkpoint(let checkpoint):
                    checkpoint.cacheID
            }
        }

        var isCheckpointPreview: Bool {
            if case .checkpoint = self {
                return true
            }
            return false
        }

        var thumbnailMaxPixelSize: CGFloat {
            switch self {
                case .checkpoint:
                    return 256
                case .activeFile, .excalidrawFile:
                    return 720
            }
        }
    }

    struct CheckpointPreviewSource {
        let objectID: NSManagedObjectID
        let cacheID: String
    }

    private struct Job {
        let source: Source
        let colorScheme: ColorScheme
        let forceRefresh: Bool
        let priority: Priority
        let sequence: Int
        let retryCount: Int

        var cacheKey: String {
            FileItemPreviewCache.cacheKey(forID: source.id, colorScheme: colorScheme) as String
        }
    }

    private enum GenerationResult: Equatable {
        case completed
        case retry
    }

    private weak var fileState: FileState?
    private weak var lockedContentState: LockedContentStateStore?
    private weak var context: NSManagedObjectContext?

    private var queue: [Job] = []
    private var queuedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    private var nextSequence = 0
    private var processingTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var currentColorScheme: ColorScheme = .light
    private var lastRecentlyVisiblePrewarmKey: CoverPrewarmKey?
    private var lastLibraryPrewarmAt: [ColorScheme: Date] = [:]

    private let cache = FileItemPreviewCache.shared
    private let logger = Logger(label: "FileCoverCacheCoordinator")
    private let maximumRetryCount = 8
    private let libraryPrewarmMinimumInterval: TimeInterval = 10 * 60
    private var cloudStorageContentObserver: NSObjectProtocol?

    private struct CoverPrewarmKey: Equatable {
        let colorScheme: ColorScheme
        let fileIDs: [String]
    }

    private init() {
        cloudStorageContentObserver = NotificationCenter.default.addObserver(
            forName: .cloudStorageDocumentContentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reference = notification.object as? CloudStorageDocumentReference else {
                return
            }
            Task { @MainActor [weak self] in
                self?.refreshCover(
                    for: .cloudStorageFile(reference),
                    priority: .userInitiated
                )
            }
        }
    }

    func register(
        fileState: FileState,
        lockedContentState: LockedContentStateStore,
        context: NSManagedObjectContext
    ) {
        self.fileState = fileState
        self.lockedContentState = lockedContentState
        self.context = context
    }

    func request(
        source: Source,
        colorScheme: ColorScheme,
        priority: Priority = .background,
        forceRefresh: Bool = false
    ) {
        currentColorScheme = colorScheme
        let cacheKey = FileItemPreviewCache.cacheKey(
            forID: source.id,
            colorScheme: colorScheme
        ) as String

        if !forceRefresh,
           cache.object(forKey: cacheKey as NSString) != nil {
            return
        }

        if let existingJob = queue.first(where: { $0.cacheKey == cacheKey }) {
            let shouldReplace = forceRefresh || priority.rawValue > existingJob.priority.rawValue
            guard shouldReplace else { return }
            queue.removeAll { $0.cacheKey == cacheKey }
            queuedKeys.remove(cacheKey)
        }

        if inFlightKeys.contains(cacheKey) {
            guard forceRefresh, !queuedKeys.contains(cacheKey) else { return }
            enqueue(
                source: source,
                colorScheme: colorScheme,
                forceRefresh: true,
                priority: priority,
                cacheKey: cacheKey,
                retryCount: 0
            )
            return
        }
        guard !shouldSkipLockedSource(source) else { return }

        enqueue(
            source: source,
            colorScheme: colorScheme,
            forceRefresh: forceRefresh,
            priority: priority,
            cacheKey: cacheKey,
            retryCount: 0
        )
    }

    private func enqueue(
        source: Source,
        colorScheme: ColorScheme,
        forceRefresh: Bool,
        priority: Priority,
        cacheKey: String,
        retryCount: Int
    ) {
        queuedKeys.insert(cacheKey)
        queue.append(Job(
            source: source,
            colorScheme: colorScheme,
            forceRefresh: forceRefresh,
            priority: priority,
            sequence: nextSequence,
            retryCount: retryCount
        ))
        nextSequence += 1
        sortQueue()
        startProcessingIfNeeded()
    }

    func request(
        activeFile: FileState.ActiveFile,
        colorScheme: ColorScheme,
        priority: Priority = .background,
        forceRefresh: Bool = false
    ) {
        request(
            source: .activeFile(activeFile),
            colorScheme: colorScheme,
            priority: priority,
            forceRefresh: forceRefresh
        )
    }

    func refreshCover(
        for activeFile: FileState.ActiveFile,
        priority: Priority = .userInitiated
    ) {
        let otherColorScheme: ColorScheme = currentColorScheme == .light
            ? .dark
            : .light
        cache.removePreviewCache(
            forID: activeFile.id,
            colorScheme: otherColorScheme
        )
        request(
            activeFile: activeFile,
            colorScheme: currentColorScheme,
            priority: priority,
            forceRefresh: true
        )
    }

    func request<Checkpoint: FileCheckpointRepresentable>(
        checkpoint: Checkpoint,
        colorScheme: ColorScheme,
        priority: Priority = .background,
        forceRefresh: Bool = false
    ) {
        request(
            source: .checkpoint(.init(
                objectID: checkpoint.objectID,
                cacheID: Self.checkpointPreviewID(for: checkpoint)
            )),
            colorScheme: colorScheme,
            priority: priority,
            forceRefresh: forceRefresh
        )
    }

    static func checkpointPreviewID<Checkpoint: FileCheckpointRepresentable>(for checkpoint: Checkpoint) -> String {
        if let fileCheckpoint = checkpoint as? FileCheckpoint,
           let id = fileCheckpoint.id?.uuidString {
            return "checkpoint:\(id)"
        }

        if let localFileCheckpoint = checkpoint as? LocalFileCheckpoint,
           let id = localFileCheckpoint.id?.uuidString {
            return "checkpoint:\(id)"
        }

        return "checkpoint:\(checkpoint.objectID.uriRepresentation().absoluteString)"
    }

    func prioritizeRecentlyVisibleFiles(
        _ files: [FileState.ActiveFile],
        colorScheme: ColorScheme,
        limit: Int = 20
    ) {
        currentColorScheme = colorScheme
        let files = Array(files.prefix(limit))
        let prewarmKey = CoverPrewarmKey(
            colorScheme: colorScheme,
            fileIDs: files.map(\.id)
        )
        guard prewarmKey != lastRecentlyVisiblePrewarmKey else { return }
        lastRecentlyVisiblePrewarmKey = prewarmKey

        for file in files {
            request(
                activeFile: file,
                colorScheme: colorScheme,
                priority: .recently
            )
        }
    }

    func scheduleLibraryPrewarm(
        colorScheme: ColorScheme,
        delay: UInt64 = 1_500_000_000
    ) {
        currentColorScheme = colorScheme
        prewarmTask?.cancel()
        prewarmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            enqueueRecentlyUsedCovers(colorScheme: colorScheme)
            let now = Date()
            if now.timeIntervalSince(lastLibraryPrewarmAt[colorScheme] ?? .distantPast) >= libraryPrewarmMinimumInterval {
                lastLibraryPrewarmAt[colorScheme] = now
                enqueueMissingLibraryCovers(colorScheme: colorScheme)
            }
        }
    }

    func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
    }

    func refreshLibraryCoversForLockStateChange(colorScheme: ColorScheme) {
        currentColorScheme = colorScheme
        guard let context,
              let lockedContentState else {
            return
        }

        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == NO")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "visitedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do {
            let files = try context.fetch(fetchRequest)
            for file in files {
                let activeFile = FileState.ActiveFile.file(file)
                switch lockedContentState.previewLockState(for: activeFile) {
                    case .locked:
                        continue

                    case .temporarilyUnlocked:
                        request(
                            activeFile: activeFile,
                            colorScheme: colorScheme,
                            priority: .recently,
                            forceRefresh: false
                        )

                    case .plaintext:
                        request(
                            activeFile: activeFile,
                            colorScheme: colorScheme,
                            priority: .background
                        )

                    case .none:
                        continue
                }
            }
        } catch {
            logger.warning("Failed to refresh library covers for lock state change: \(error)")
        }
    }

    func cacheCurrentViewportPreview(for activeFile: FileState.ActiveFile) async {
        let source = Source.activeFile(activeFile)
        let coordinator: ExcalidrawCanvasView.Coordinator? = {
            if case .collaborationFile = activeFile {
                return fileState?.excalidrawCollaborationWebCoordinator
            }
            return fileState?.excalidrawWebCoordinator
        }()
        let requiresLoadedFileMatch: Bool = {
            if case .collaborationFile = activeFile {
                return false
            }
            return true
        }()
        guard !shouldSkipLockedSource(source),
              let coordinator,
              !coordinator.isLoading,
              (!requiresLoadedFileMatch || coordinator.documentSyncController.currentLoadedFileID == activeFile.id) else {
            return
        }

        do {
            let image = try await coordinator.exportCurrentViewportToPNG()
            guard let thumbnail = makeThumbnail(
                from: image,
                maxPixelSize: source.thumbnailMaxPixelSize
            ) else {
                logger.warning("Failed to downsample current viewport preview for \(activeFile.id)")
                return
            }
            let cacheKey = FileItemPreviewCache.cacheKey(
                forID: activeFile.id,
                colorScheme: currentColorScheme
            )
            cache.setObject(thumbnail, forKey: cacheKey)
            logger.debug("Cached current viewport preview for \(activeFile.id)")
            NotificationCenter.default.post(
                name: .filePreviewDidUpdate,
                object: activeFile.id
            )
        } catch {
            logger.debug("Failed to cache current viewport preview for \(activeFile.id): \(error)")
        }
    }

    private func sortQueue() {
        queue.sort {
            if $0.priority.rawValue != $1.priority.rawValue {
                return $0.priority.rawValue > $1.priority.rawValue
            }
            return $0.sequence < $1.sequence
        }
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor in
            await processQueue()
        }
    }

    private func processQueue() async {
        defer {
            processingTask = nil
            if !queue.isEmpty {
                startProcessingIfNeeded()
            }
        }

        while !Task.isCancelled, !queue.isEmpty {
            guard let jobIndex = queue.firstIndex(where: { !shouldDeferForActiveFile($0) }) else {
                try? await Task.sleep(nanoseconds: 750_000_000)
                continue
            }

            let job = queue.remove(at: jobIndex)
            queuedKeys.remove(job.cacheKey)

            if !job.forceRefresh,
               cache.object(forKey: job.cacheKey as NSString) != nil {
                continue
            }

            inFlightKeys.insert(job.cacheKey)
            let result = await generate(job)
            inFlightKeys.remove(job.cacheKey)

            if result == .retry {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                requeue(job)
            }
        }
    }

    private func shouldDeferForActiveFile(_ job: Job) -> Bool {
        !job.source.isCheckpointPreview
        && job.priority.rawValue < Priority.userInitiated.rawValue
        && fileState?.currentActiveFile != nil
    }

    private func requeue(_ job: Job) {
        guard job.retryCount < maximumRetryCount else {
            logger.warning("Dropped preview generation after retries for \(job.source.id)")
            return
        }

        guard (job.forceRefresh || cache.object(forKey: job.cacheKey as NSString) == nil),
              !queuedKeys.contains(job.cacheKey),
              !inFlightKeys.contains(job.cacheKey) else {
            return
        }

        queuedKeys.insert(job.cacheKey)
        queue.append(Job(
            source: job.source,
            colorScheme: job.colorScheme,
            forceRefresh: job.forceRefresh,
            priority: job.priority,
            sequence: nextSequence,
            retryCount: job.retryCount + 1
        ))
        nextSequence += 1
        sortQueue()
    }

    private func enqueueRecentlyUsedCovers(colorScheme: ColorScheme) {
        guard let context else { return }

        let fileRequest = NSFetchRequest<File>(entityName: "File")
        fileRequest.predicate = NSPredicate(format: "inTrash == NO")
        fileRequest.sortDescriptors = [
            NSSortDescriptor(key: "visitedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        fileRequest.fetchLimit = 20

        let collaborationRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
        collaborationRequest.predicate = NSPredicate(format: "inTrash == NO")
        collaborationRequest.sortDescriptors = [
            NSSortDescriptor(key: "visitedAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        collaborationRequest.fetchLimit = 20

        do {
            let files = try context.fetch(fileRequest)
            let collaborationFiles = try context.fetch(collaborationRequest)
            let recentFiles: [FileState.ActiveFile] = files.map { .file($0) }
                + collaborationFiles.map { .collaborationFile($0) }

            for file in recentFiles.sorted(by: { lhs, rhs in
                recentDate(for: lhs) > recentDate(for: rhs)
            }).prefix(20) {
                request(
                    activeFile: file,
                    colorScheme: colorScheme,
                    priority: .recently
                )
            }
        } catch {
            logger.warning("Failed to enqueue recently used cover prewarm: \(error)")
        }
    }

    private func enqueueMissingLibraryCovers(colorScheme: ColorScheme) {
        guard let context else { return }

        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "inTrash == NO")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do {
            let files = try context.fetch(fetchRequest)
            for file in files {
                let activeFile = FileState.ActiveFile.file(file)
                if let lockState = lockedContentState?.previewLockState(for: activeFile),
                   lockState == .locked {
                    continue
                }
                request(
                    activeFile: activeFile,
                    colorScheme: colorScheme,
                    priority: .background
                )
            }
        } catch {
            logger.warning("Failed to enqueue library cover prewarm: \(error)")
        }
    }

    private func shouldSkipLockedSource(_ source: Source) -> Bool {
        guard case .activeFile(let activeFile) = source,
              case .file = activeFile,
              let lockState = lockedContentState?.previewLockState(for: activeFile) else {
            return false
        }

        return lockState == .locked
    }

    private func recentDate(for file: FileState.ActiveFile) -> Date {
        switch file {
            case .file(let file):
                return file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
            case .collaborationFile(let file):
                return file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
            case .localFile(let url), .temporaryFile(let url):
                let resourceValues = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .creationDateKey
                ])
                return max(
                    resourceValues?.contentModificationDate ?? .distantPast,
                    resourceValues?.creationDate ?? .distantPast
                )
            case .cloudStorageFile:
                return .distantPast
        }
    }

    private func generate(_ job: Job) async -> GenerationResult {
        guard let coordinator = await waitForPreviewExporter() else {
            logger.debug("Preview export coordinator unavailable for \(job.source.id), retry=\(job.retryCount)")
            return .retry
        }

        do {
            var excalidrawFile: ExcalidrawFile
            let mediaHydrationFileObjectID: NSManagedObjectID?

            switch job.source {
                case .activeFile(let activeFile):
                    switch activeFile {
                        case .file(let file):
                            mediaHydrationFileObjectID = file.objectID
                            if let lockedContentState {
                                await lockedContentState.refresh(
                                    fileObjectID: file.objectID,
                                    fileID: activeFile.id
                                )
                                if lockedContentState.previewLockState(for: activeFile) == .locked {
                                    return .completed
                                }
                            }
                            let content = try await file.loadContent(applyingLocalViewport: true)
                            excalidrawFile = try ExcalidrawFile(data: content, id: activeFile.id)

                        case .localFile(let url):
                            mediaHydrationFileObjectID = nil
                            excalidrawFile = try await loadLocalFileForPreview(at: url)

                        case .temporaryFile(let url):
                            mediaHydrationFileObjectID = nil
                            excalidrawFile = try ExcalidrawFile(contentsOf: url)

                        case .collaborationFile(let collaborationFile):
                            mediaHydrationFileObjectID = nil
                            let content = try await collaborationFile.loadContent()
                            excalidrawFile = try ExcalidrawFile(
                                data: content,
                                id: collaborationFile.id?.uuidString
                            )

                        case .cloudStorageFile(let reference):
                            mediaHydrationFileObjectID = nil
                            let documentStore = CloudStorageDocumentStore.shared
                            guard let content = try documentStore.cachedContent(for: reference) else {
                                return .completed
                            }
                            excalidrawFile = try ExcalidrawFile(
                                data: content,
                                id: reference.id
                            )
                    }

                case .excalidrawFile(let file):
                    mediaHydrationFileObjectID = nil
                    excalidrawFile = file

                case .checkpoint(let checkpointSource):
                    guard let context else {
                        return .retry
                    }

                    let object = try context.existingObject(with: checkpointSource.objectID)
                    if let checkpoint = object as? FileCheckpoint {
                        mediaHydrationFileObjectID = checkpoint.file?.objectID
                        let content = try await checkpoint.loadContent()
                        excalidrawFile = try ExcalidrawFile(
                            data: content,
                            id: checkpointSource.cacheID
                        )
                    } else if let checkpoint = object as? LocalFileCheckpoint,
                              let content = checkpoint.content {
                        mediaHydrationFileObjectID = nil
                        excalidrawFile = try ExcalidrawFile(
                            data: content,
                            id: checkpointSource.cacheID
                        )
                    } else {
                        return .completed
                    }
            }

            excalidrawFile = await hydrateMediaForPreview(
                excalidrawFile,
                fileObjectID: mediaHydrationFileObjectID
            )

            guard !Task.isCancelled else { return .completed }

            let image: PlatformImage
            do {
                image = try await exportViewportPreview(
                    for: excalidrawFile,
                    colorScheme: job.colorScheme,
                    coordinator: coordinator
                )
            } catch {
                guard !Task.isCancelled else { return .completed }
                logger.debug("Failed to export viewport preview for \(job.source.id): \(error), retry=\(job.retryCount)")
                return .retry
            }

            guard !Task.isCancelled else { return .completed }

            let thumbnail = makeThumbnail(
                from: image,
                maxPixelSize: job.source.thumbnailMaxPixelSize
            )
            guard let thumbnail else {
                logger.warning("Failed to downsample preview image for \(job.source.id)")
                return .completed
            }

            cache.setObject(thumbnail, forKey: job.cacheKey as NSString)
            logger.debug("Cached generated preview for \(job.source.id)")
            NotificationCenter.default.post(
                name: .filePreviewDidUpdate,
                object: job.source.id
            )
            return .completed
        } catch {
            guard !Task.isCancelled else { return .completed }
            logger.debug("Failed to generate preview for \(job.source.id): \(error)")
            return .completed
        }
    }

    private func exportViewportPreview(
        for excalidrawFile: ExcalidrawFile,
        colorScheme: ColorScheme,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> PlatformImage {
        var exportFile = excalidrawFile
        if exportFile.content != nil {
            try exportFile.updateContentFilesFromFiles()
        }
        let sceneData = try exportFile.content ?? JSONEncoder().encode(exportFile)
        return try await coordinator.exportViewportPreviewToPNG(
            sceneData: sceneData,
            colorScheme: colorScheme
        )
    }

    private func waitForPreviewExporter() async -> ExcalidrawCanvasView.Coordinator? {
        var lastReadinessSummary = "coordinator=nil"
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }

            if let coordinator = fileState?.excalidrawWebCoordinator {
                lastReadinessSummary = coordinator.previewExportReadinessSummary
                if coordinator.isReadyForPreviewExport {
                    return coordinator
                }
            } else {
                lastReadinessSummary = "coordinator=nil"
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        logger.debug("Preview export coordinator unavailable: \(lastReadinessSummary)")
        return nil
    }

    private func loadLocalFileForPreview(at url: URL) async throws -> ExcalidrawFile {
        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: url) {
            try await FileCoordinator.shared.downloadFile(url: url)
            return try ExcalidrawFile(contentsOf: url)
        }
    }

    private func hydrateMediaForPreview(
        _ excalidrawFile: ExcalidrawFile,
        fileObjectID: NSManagedObjectID?
    ) async -> ExcalidrawFile {
        guard let fileObjectID,
              excalidrawFile.files.isEmpty,
              excalidrawFile.elements.contains(where: \.isImageElement) else {
            return excalidrawFile
        }

        do {
            let resources = try await PersistenceController.shared
                .mediaItemRepository
                .getResourceFiles(forFile: fileObjectID)
            guard !resources.isEmpty else { return excalidrawFile }

            var hydratedFile = excalidrawFile
            let resourceFiles = Dictionary(
                resources.map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            hydratedFile.files = resourceFiles.merging(hydratedFile.files) { _, fileResource in
                fileResource
            }
            return hydratedFile
        } catch {
            logger.warning("Failed to hydrate media for preview \(excalidrawFile.id): \(error)")
            return excalidrawFile
        }
    }

    private func makeThumbnail(
        from image: PlatformImage,
        maxPixelSize: CGFloat
    ) -> PlatformImage? {
        guard let cgThumb = image.downsampledCGImage(maxPixelSize: maxPixelSize) else {
            return nil
        }
#if canImport(UIKit)
        return UIImage(cgImage: cgThumb)
#elseif canImport(AppKit)
        return NSImage(
            cgImage: cgThumb,
            size: CGSize(
                width: CGFloat(cgThumb.width),
                height: CGFloat(cgThumb.height)
            )
        )
#endif
    }
}

private extension ExcalidrawElement {
    var isImageElement: Bool {
        if case .image = self {
            return true
        }
        return false
    }
}
