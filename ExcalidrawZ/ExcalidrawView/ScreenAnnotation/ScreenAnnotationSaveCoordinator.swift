#if os(macOS)
import AppKit
import Logging

@MainActor
final class ScreenAnnotationSaveCoordinator {
    let configuration: ScreenAnnotationSaveConfiguration

    private let logger = Logger(label: "ScreenAnnotationSaveCoordinator")
    private let taskManager = ScreenAnnotationSaveTaskManager.shared
    private let persistence: ScreenAnnotationSavePersistence

    init() {
        let configuration = ScreenAnnotationSaveConfiguration()
        self.configuration = configuration
        self.persistence = ScreenAnnotationSavePersistence(
            configuration: configuration
        )
    }

    func submit(
        destination: ScreenAnnotationSaveDestination,
        format: ScreenAnnotationSaveFormat,
        region: CGRect?,
        session: ScreenAnnotationSession,
        screen: NSScreen,
        fileState: FileState?,
        annotationWindow: NSWindow?,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        let saveID = UUID().uuidString
        let submittedAt = Date()
        logger.debug(
            "Preparing screen annotation save id=\(saveID) destination=\(destination.title) format=\(format.rawValue)"
        )

        Task { @MainActor [weak self, weak session] in
            guard let self, let session else {
                completion(false)
                return
            }

            do {
                let preparedSave = try await prepareSave(
                    destination: destination,
                    format: format,
                    region: region,
                    session: session,
                    fileState: fileState,
                    screen: screen,
                    annotationWindow: annotationWindow,
                    saveID: saveID
                )
                let preparationDuration = Self.milliseconds(from: submittedAt)
                logger.info(
                    "Prepared screen annotation save id=\(saveID) durationMs=\(preparationDuration)"
                )

                let queuedSave: PreparedScreenAnnotationSave
                if destination == .customLocation {
                    completion(true)
                    await Self.waitForNextMainRunLoop()
                    guard let selectedURL = ScreenAnnotationSaveService
                        .chooseCustomLocation(format: format) else {
                        logger.debug(
                            "Cancelled custom screen annotation save id=\(saveID)"
                        )
                        return
                    }
                    queuedSave = preparedSave.withCustomLocationURL(selectedURL)
                } else {
                    queuedSave = preparedSave
                }

                let persistence = persistence
                taskManager.submit(id: saveID) {
                    try await persistence.persist(
                        queuedSave,
                        saveID: saveID
                    )
                }
                if destination != .customLocation {
                    completion(true)
                }
            } catch {
                let preparationDuration = Self.milliseconds(from: submittedAt)
                logger.error(
                    "Failed to prepare screen annotation save id=\(saveID) durationMs=\(preparationDuration) error=\(error)"
                )
                session.report(error)
                completion(false)
            }
        }
    }

    private func prepareSave(
        destination: ScreenAnnotationSaveDestination,
        format: ScreenAnnotationSaveFormat,
        region: CGRect?,
        session: ScreenAnnotationSession,
        fileState: FileState?,
        screen: NSScreen,
        annotationWindow: NSWindow?,
        saveID: String
    ) async throws -> PreparedScreenAnnotationSave {
        let captureStartedAt = Date()
        let captured: NSImage
        if format == .raw,
           let frozenBackgroundImage = session.frozenBackgroundImage {
            captured = frozenBackgroundImage
            logger.debug(
                "Reused frozen background id=\(saveID) durationMs=0"
            )
        } else {
            if format != .raw {
                try await session.deselectElementsForCapture()
            }
            guard let image = try await ScreenAnnotationCaptureService.capture(
                screen,
                excludingWindowNumber: format == .raw
                    ? annotationWindow?.windowNumber
                    : nil
            ) else {
                throw ScreenAnnotationSaveService.SaveError.imageUnavailable
            }
            captured = image
            logger.debug(
                "Captured screen annotation id=\(saveID) durationMs=\(Self.milliseconds(from: captureStartedAt))"
            )
        }

        let cropStartedAt = Date()
        let image = try ScreenAnnotationSaveService.croppedImage(
            captured,
            to: region
        )
        logger.debug(
            "Prepared capture region id=\(saveID) durationMs=\(Self.milliseconds(from: cropStartedAt))"
        )

        guard format == .raw || destination.isExcalidrawFile else {
            return .bitmap(
                image: image,
                format: format,
                destination: destination,
                customLocationURL: nil
            )
        }

        let documentStartedAt = Date()
        let documentImageFormat: ScreenAnnotationSaveFormat = format == .raw
            ? .png
            : format
        let documentImageData = try ScreenAnnotationSaveService.imageData(
            from: image,
            format: documentImageFormat
        )
        let viewportRect = CGRect(origin: .zero, size: captured.size)
        let selectionRect = region?.intersection(viewportRect)
        var document = try await session.makeAnnotationDocument(
            imageData: documentImageData,
            imageFormat: documentImageFormat,
            mode: format == .raw ? .raw : .bitmap,
            viewportRect: viewportRect,
            selectionRect: selectionRect
        )
        document.name = "Screen Annotations"
        logger.debug(
            "Built raw annotation document id=\(saveID) durationMs=\(Self.milliseconds(from: documentStartedAt))"
        )
        return .document(
            document: document,
            destination: destination,
            fileState: fileState,
            customLocationURL: nil
        )
    }

    private static func milliseconds(from start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }

    private static func waitForNextMainRunLoop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
#endif
