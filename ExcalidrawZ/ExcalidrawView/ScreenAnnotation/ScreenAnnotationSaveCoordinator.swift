#if os(macOS)
import AppKit
import CoreData
import Logging

@MainActor
final class ScreenAnnotationSaveCoordinator {
    let configuration = ScreenAnnotationSaveConfiguration()

    private let logger = Logger(label: "ScreenAnnotationSaveCoordinator")

    func save(
        destination: ScreenAnnotationSaveDestination,
        format: ScreenAnnotationSaveFormat,
        region: CGRect?,
        session: ScreenAnnotationSession,
        screen: NSScreen,
        fileState: FileState?,
        annotationWindow: NSWindow?,
        captureFinished: @MainActor @escaping () -> Void
    ) async -> Bool {
        var didFinishCapture = false
        defer {
            if !didFinishCapture {
                captureFinished()
            }
        }

        do {
            let captured: NSImage
            if format == .raw,
               let frozenBackgroundImage = session.frozenBackgroundImage {
                captured = frozenBackgroundImage
            } else {
                guard let image = try await ScreenAnnotationCaptureService.capture(
                    screen,
                    excludingWindowNumber: format == .raw
                        ? annotationWindow?.windowNumber
                        : nil
                ) else {
                    throw ScreenAnnotationSaveService.SaveError.imageUnavailable
                }
                captured = image
            }
            didFinishCapture = true
            captureFinished()

            let image = try ScreenAnnotationSaveService.croppedImage(
                captured,
                to: region
            )
            if format == .raw {
                return try await saveRawCapture(
                    image,
                    fullCaptureSize: captured.size,
                    region: region,
                    destination: destination,
                    session: session,
                    fileState: fileState,
                    annotationWindow: annotationWindow
                )
            }

            return try saveBitmapCapture(
                image,
                format: format,
                destination: destination,
                annotationWindow: annotationWindow
            )
        } catch {
            logger.error("Failed to save screen annotation: \(error)")
            session.report(error)
            return false
        }
    }

    private func saveRawCapture(
        _ image: NSImage,
        fullCaptureSize: CGSize,
        region: CGRect?,
        destination: ScreenAnnotationSaveDestination,
        session: ScreenAnnotationSession,
        fileState: FileState?,
        annotationWindow: NSWindow?
    ) async throws -> Bool {
        let backgroundImageData = try ScreenAnnotationSaveService.imageData(
            from: image,
            format: .png
        )
        let viewportRect = CGRect(origin: .zero, size: fullCaptureSize)
        let selectionRect = region?.intersection(viewportRect)
        var document = try await session.makeRawAnnotationDocument(
            backgroundImageData: backgroundImageData,
            viewportRect: viewportRect,
            selectionRect: selectionRect
        )
        document.name = "Screen Annotations"
        return try await saveRawDocument(
            document,
            to: destination,
            fileState: fileState,
            annotationWindow: annotationWindow
        )
    }

    private func saveBitmapCapture(
        _ image: NSImage,
        format: ScreenAnnotationSaveFormat,
        destination: ScreenAnnotationSaveDestination,
        annotationWindow: NSWindow?
    ) throws -> Bool {
        let data = try ScreenAnnotationSaveService.imageData(
            from: image,
            format: format
        )

        switch destination {
            case .clipboard:
                ScreenAnnotationSaveService.copyToClipboard(
                    data,
                    format: format
                )
            case .downloads:
                try ScreenAnnotationSaveService.saveToDownloads(
                    data,
                    format: format
                )
            case .customLocation:
                return try ScreenAnnotationSaveService.saveToCustomLocation(
                    data,
                    format: format,
                    above: annotationWindow
                ) != nil
            case .newFile, .libraryFile, .localFile:
                throw ScreenAnnotationSaveError.invalidDestinationFormat
        }
        return true
    }

    private func saveRawDocument(
        _ document: ExcalidrawFile,
        to destination: ScreenAnnotationSaveDestination,
        fileState: FileState?,
        annotationWindow: NSWindow?
    ) async throws -> Bool {
        guard let documentData = document.content else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        switch destination {
            case .newFile:
                try await createAnnotationFile(
                    document,
                    fileState: fileState
                )
            case .libraryFile(let objectID, _):
                try await insertRawDocument(
                    document,
                    into: .libraryFile(objectID),
                    fileState: fileState
                )
            case .localFile(let url):
                try await insertRawDocument(
                    document,
                    into: .localFile(url),
                    fileState: fileState
                )
            case .clipboard:
                ScreenAnnotationSaveService.copyToClipboard(
                    documentData,
                    format: .raw
                )
            case .downloads:
                try ScreenAnnotationSaveService.saveToDownloads(
                    documentData,
                    format: .raw
                )
            case .customLocation:
                return try ScreenAnnotationSaveService.saveToCustomLocation(
                    documentData,
                    format: .raw,
                    above: annotationWindow
                ) != nil
        }
        return true
    }

    private func createAnnotationFile(
        _ document: ExcalidrawFile,
        fileState: FileState?
    ) async throws {
        guard let fileState else {
            throw ScreenAnnotationSaveError.fileStateUnavailable
        }

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
        guard let file = context.object(
            with: result.fileObjectID
        ) as? File else {
            throw ScreenAnnotationSaveError.targetFileUnavailable
        }

        let activeFile = FileState.ActiveFile.file(file)
        let destination = ScreenAnnotationSaveDestination.libraryFile(
            objectID: result.fileObjectID,
            name: document.name ?? "Screen Annotations"
        )
        configuration.selectFileDestination(destination)
        fileState.currentActiveGroup = .group(defaultGroup)
        fileState.setActiveFile(activeFile)
    }

    private func insertRawDocument(
        _ document: ExcalidrawFile,
        into target: ScreenAnnotationFileTarget,
        fileState: FileState?
    ) async throws {
        let coordinator = try await openCanvas(
            for: target,
            fileState: fileState
        )
        try await ScreenAnnotationDocumentBridge.insert(
            document,
            into: coordinator.webView
        )
        coordinator.documentSyncController.scheduleProgrammaticMutationCommit(
            reason: "insertRawScreenAnnotation"
        )
    }

    private func openCanvas(
        for target: ScreenAnnotationFileTarget,
        fileState: FileState?
    ) async throws -> ExcalidrawCanvasView.Coordinator {
        guard let fileState else {
            throw ScreenAnnotationSaveError.fileStateUnavailable
        }

        let activeFile: FileState.ActiveFile
        switch target {
            case .libraryFile(let objectID):
                let context = PersistenceController.shared.container.viewContext
                guard let object = try? context.existingObject(
                    with: objectID
                ),
                      let file = object as? File else {
                    throw ScreenAnnotationSaveError.targetFileUnavailable
                }
                if let group = file.group {
                    fileState.currentActiveGroup = .group(group)
                }
                activeFile = .file(file)
            case .localFile(let url):
                activeFile = .localFile(url)
        }

        guard await fileState.requestActiveFileChange(activeFile) else {
            throw ScreenAnnotationSaveError.targetFileUnavailable
        }
        return try await waitForCanvas(
            fileID: activeFile.id,
            fileState: fileState
        )
    }

    private func waitForCanvas(
        fileID: String,
        fileState: FileState
    ) async throws -> ExcalidrawCanvasView.Coordinator {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let coordinator = fileState.excalidrawWebCoordinator,
               coordinator.documentSyncController.currentLoadedFileID
                == fileID {
                return coordinator
            }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        throw ScreenAnnotationSaveError.canvasLoadTimedOut
    }
}

private enum ScreenAnnotationFileTarget {
    case libraryFile(NSManagedObjectID)
    case localFile(URL)
}

private enum ScreenAnnotationSaveError: LocalizedError {
    case fileStateUnavailable
    case targetFileUnavailable
    case defaultGroupUnavailable
    case canvasLoadTimedOut
    case invalidDestinationFormat

    var errorDescription: String? {
        switch self {
            case .fileStateUnavailable:
                "No ExcalidrawZ window is available."
            case .targetFileUnavailable:
                "The selected Excalidraw file is unavailable."
            case .defaultGroupUnavailable:
                "The default Excalidraw group is unavailable."
            case .canvasLoadTimedOut:
                "The selected Excalidraw file did not finish loading."
            case .invalidDestinationFormat:
                "Excalidraw file destinations require Raw format."
        }
    }
}
#endif
