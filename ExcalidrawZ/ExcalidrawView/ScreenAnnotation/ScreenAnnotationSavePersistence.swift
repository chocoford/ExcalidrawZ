#if os(macOS)
import AppKit
import CoreData
import Logging

enum PreparedScreenAnnotationSave {
    case document(
        document: ExcalidrawFile,
        destination: ScreenAnnotationSaveDestination,
        fileState: FileState?,
        customLocationURL: URL?
    )
    case bitmap(
        image: NSImage,
        format: ScreenAnnotationSaveFormat,
        imageQuality: ScreenAnnotationImageQuality,
        destination: ScreenAnnotationSaveDestination,
        customLocationURL: URL?
    )

    func withCustomLocationURL(_ url: URL) -> Self {
        switch self {
            case .document(let document, let destination, let fileState, _):
                return .document(
                    document: document,
                    destination: destination,
                    fileState: fileState,
                    customLocationURL: url
                )
            case .bitmap(
                let image,
                let format,
                let imageQuality,
                let destination,
                _
            ):
                return .bitmap(
                    image: image,
                    format: format,
                    imageQuality: imageQuality,
                    destination: destination,
                    customLocationURL: url
                )
        }
    }
}

@MainActor
final class ScreenAnnotationSavePersistence {
    private let configuration: ScreenAnnotationSaveConfiguration
    private let logger = Logger(label: "ScreenAnnotationSavePersistence")

    init(configuration: ScreenAnnotationSaveConfiguration) {
        self.configuration = configuration
    }

    func persist(
        _ preparedSave: PreparedScreenAnnotationSave,
        saveID: String
    ) async throws {
        switch preparedSave {
            case .document(
                let document,
                let destination,
                let fileState,
                let customLocationURL
            ):
                try await saveDocument(
                    document,
                    to: destination,
                    fileState: fileState,
                    customLocationURL: customLocationURL,
                    saveID: saveID
                )
            case .bitmap(
                let image,
                let format,
                let imageQuality,
                let destination,
                let customLocationURL
            ):
                let startedAt = Date()
                try saveBitmapCapture(
                    image,
                    format: format,
                    imageQuality: imageQuality,
                    destination: destination,
                    customLocationURL: customLocationURL
                )
                logger.debug(
                    "Encoded and persisted bitmap id=\(saveID) durationMs=\(Self.milliseconds(from: startedAt))"
                )
        }
    }

    private func saveBitmapCapture(
        _ image: NSImage,
        format: ScreenAnnotationSaveFormat,
        imageQuality: ScreenAnnotationImageQuality,
        destination: ScreenAnnotationSaveDestination,
        customLocationURL: URL?
    ) throws {
        let data = try ScreenAnnotationSaveService.imageData(
            from: image,
            format: format,
            jpegCompressionFactor: imageQuality.jpegCompressionFactor
        )

        switch destination {
            case .clipboard:
                ScreenAnnotationSaveService.copyToClipboard(
                    data,
                    format: format
                )
            case .customLocation:
                guard let customLocationURL else {
                    throw ScreenAnnotationSaveError.customLocationUnavailable
                }
                try ScreenAnnotationSaveService.save(
                    data,
                    to: customLocationURL
                )
            case .newFile, .libraryFile, .localFile:
                throw ScreenAnnotationSaveError.invalidDestinationFormat
        }
    }

    private func saveDocument(
        _ document: ExcalidrawFile,
        to destination: ScreenAnnotationSaveDestination,
        fileState: FileState?,
        customLocationURL: URL?,
        saveID: String
    ) async throws {
        guard let documentData = document.content else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        switch destination {
            case .newFile:
                let startedAt = Date()
                try await createAnnotationFile(document)
                logger.debug(
                    "Created annotation file id=\(saveID) durationMs=\(Self.milliseconds(from: startedAt))"
                )
            case .libraryFile(let objectID, _):
                try await insertDocument(
                    document,
                    into: .libraryFile(objectID),
                    fileState: fileState,
                    saveID: saveID
                )
            case .localFile(let url):
                try await insertDocument(
                    document,
                    into: .localFile(url),
                    fileState: fileState,
                    saveID: saveID
                )
            case .clipboard:
                let startedAt = Date()
                ScreenAnnotationSaveService.copyToClipboard(
                    documentData,
                    format: .raw
                )
                logger.debug(
                    "Copied raw annotation id=\(saveID) durationMs=\(Self.milliseconds(from: startedAt))"
                )
            case .customLocation:
                guard let customLocationURL else {
                    throw ScreenAnnotationSaveError.customLocationUnavailable
                }
                try ScreenAnnotationSaveService.save(
                    documentData,
                    to: customLocationURL
                )
        }
    }

    private func createAnnotationFile(_ document: ExcalidrawFile) async throws {
        var document = document
        document.appState.viewBackgroundColor = "#ffffff"
        document.content = try Self.documentData(
            document.content,
            settingCanvasBackground: "#ffffff"
        )

        let context = PersistenceController.shared.container.viewContext
        guard let defaultGroup = try PersistenceController.shared
            .getDefaultGroup(context: context) else {
            throw ScreenAnnotationSaveError.defaultGroupUnavailable
        }

        let result = try await PersistenceController.shared.fileRepository
            .createFileFromExcalidraw(
                document,
                groupObjectID: defaultGroup.objectID
            )
        let destination = ScreenAnnotationSaveDestination.libraryFile(
            objectID: result.fileObjectID,
            name: document.name ?? "Screen Annotations"
        )
        configuration.selectFileDestination(destination)
        configuration.recordSuccessfulSave(to: destination)

        if let object = try? context.existingObject(
            with: result.fileObjectID
        ),
           let file = object as? File {
            FileCoverCacheCoordinator.shared.refreshCover(
                for: .file(file)
            )
        }
    }

    private static func documentData(
        _ data: Data?,
        settingCanvasBackground color: String
    ) throws -> Data {
        guard let data,
              var document = try JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any] else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        var appState = document["appState"] as? [String: Any] ?? [:]
        appState["viewBackgroundColor"] = color
        document["appState"] = appState
        return try JSONSerialization.data(withJSONObject: document)
    }

    private func insertDocument(
        _ document: ExcalidrawFile,
        into target: ScreenAnnotationFileTarget,
        fileState: FileState?,
        saveID: String
    ) async throws {
        let prepareStartedAt = Date()
        let preparedTarget = try await prepareTarget(
            target,
            fileState: fileState
        )
        logger.debug(
            "Prepared target file id=\(saveID) durationMs=\(Self.milliseconds(from: prepareStartedAt))"
        )
        let existingMediaIDs = Set(preparedTarget.file.files.keys)

        try await OffscreenExcalidrawEditor.withEditor { editor in
            let loadStartedAt = Date()
            try await editor.load(preparedTarget.file)
            self.logger.debug(
                "Loaded target in offscreen editor id=\(saveID) durationMs=\(Self.milliseconds(from: loadStartedAt))"
            )

            let insertionStartedAt = Date()
            try await ScreenAnnotationDocumentBridge.insert(
                document,
                into: editor.webView
            )
            self.logger.debug(
                "Inserted annotation document id=\(saveID) durationMs=\(Self.milliseconds(from: insertionStartedAt))"
            )

            let snapshotStartedAt = Date()
            let updatedFile = try await editor.snapshot(
                appStatePolicy: .preserveLoadedDocument
            )
            self.logger.debug(
                "Captured offscreen snapshot id=\(saveID) durationMs=\(Self.milliseconds(from: snapshotStartedAt))"
            )

            let persistenceStartedAt = Date()
            try await FileState.persistCapturedCanvasUpdate(
                preparedTarget.saveTarget,
                with: updatedFile
            )
            self.logger.debug(
                "Persisted target file id=\(saveID) durationMs=\(Self.milliseconds(from: persistenceStartedAt))"
            )
            self.configuration.recordSuccessfulSave(
                to: preparedTarget.destination
            )

            let insertedMediaFiles = updatedFile.files.values.filter {
                !existingMediaIDs.contains($0.id)
            }
            await self.injectMediaFilesIntoMainCanvas(
                Array(insertedMediaFiles),
                fileState: fileState,
                saveID: saveID
            )
            FileCoverCacheCoordinator.shared.refreshCover(
                for: preparedTarget.activeFile
            )
        }
    }

    private func injectMediaFilesIntoMainCanvas(
        _ files: [ExcalidrawFile.ResourceFile],
        fileState: FileState?,
        saveID: String
    ) async {
        guard !files.isEmpty,
              let coordinator = fileState?.excalidrawWebCoordinator else {
            return
        }

        do {
            try await coordinator.insertMediaFiles(files)
            logger.debug(
                "Injected \(files.count) screen annotation media file(s) into main canvas id=\(saveID)"
            )
        } catch {
            // Persistence already succeeded. A newly initialized WebView will
            // recover these media from storage during its normal initial sync.
            logger.warning(
                "Failed to inject screen annotation media into main canvas id=\(saveID): \(error)"
            )
        }
    }

    private func prepareTarget(
        _ target: ScreenAnnotationFileTarget,
        fileState: FileState?
    ) async throws -> PreparedScreenAnnotationTarget {
        switch target {
            case .libraryFile(let objectID):
                let context = PersistenceController.shared.container.viewContext
                guard let object = try? context.existingObject(
                    with: objectID
                ),
                      let file = object as? File else {
                    throw ScreenAnnotationSaveError.targetFileUnavailable
                }
                let activeFile = FileState.ActiveFile.file(file)
                await fileState?
                    .flushPendingCanvasSnapshotBeforeExternalMutation(
                        fileID: activeFile.id
                    )

                let content = try await file.loadContent()
                var excalidrawFile = try ExcalidrawFile(
                    data: content,
                    id: activeFile.id
                )
                excalidrawFile.name = activeFile.name
                let resources = try await PersistenceController.shared
                    .mediaItemRepository.getResourceFiles(forFile: objectID)
                for resource in resources {
                    excalidrawFile.files[resource.id] = resource
                }
                try excalidrawFile.updateContentFilesFromFiles()

                return PreparedScreenAnnotationTarget(
                    activeFile: activeFile,
                    destination: .libraryFile(
                        objectID: objectID,
                        name: activeFile.name ?? "Untitled"
                    ),
                    file: excalidrawFile,
                    saveTarget: .init(
                        id: activeFile.id,
                        kind: .libraryFile(
                            objectURI: objectID.uriRepresentation(),
                            fileName: activeFile.name ?? "Untitled",
                            newCheckpoint: true,
                            suppressCheckpoint: false
                        )
                    )
                )

            case .localFile(let url):
                let activeFile = FileState.ActiveFile.localFile(url)
                await fileState?
                    .flushPendingCanvasSnapshotBeforeExternalMutation(
                        fileID: activeFile.id
                    )
                let content = try await FileSyncCoordinator.shared.openFile(url)
                var excalidrawFile = try ExcalidrawFile(
                    data: content,
                    id: activeFile.id
                )
                excalidrawFile.name = activeFile.name
                return PreparedScreenAnnotationTarget(
                    activeFile: activeFile,
                    destination: .localFile(url: url),
                    file: excalidrawFile,
                    saveTarget: .init(
                        id: activeFile.id,
                        kind: .localFile(
                            url: url,
                            newCheckpoint: true,
                            suppressCheckpoint: false
                        )
                    )
                )
        }
    }

    private static func milliseconds(from start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }
}

private enum ScreenAnnotationFileTarget {
    case libraryFile(NSManagedObjectID)
    case localFile(URL)
}

private struct PreparedScreenAnnotationTarget {
    var activeFile: FileState.ActiveFile
    var destination: ScreenAnnotationSaveDestination
    var file: ExcalidrawFile
    var saveTarget: FileState.CapturedCanvasSaveTarget
}

private enum ScreenAnnotationSaveError: LocalizedError {
    case targetFileUnavailable
    case defaultGroupUnavailable
    case invalidDestinationFormat
    case customLocationUnavailable

    var errorDescription: String? {
        switch self {
            case .targetFileUnavailable:
                "The selected Excalidraw file is unavailable."
            case .defaultGroupUnavailable:
                "The default Excalidraw group is unavailable."
            case .invalidDestinationFormat:
                "The selected destination does not support this format."
            case .customLocationUnavailable:
                "The selected save location is unavailable."
        }
    }
}
#endif
