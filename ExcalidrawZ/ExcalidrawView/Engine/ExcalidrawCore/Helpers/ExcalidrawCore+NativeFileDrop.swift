import Foundation
import Observation
import WebKit
#if canImport(PDFKit)
import PDFKit
#endif

struct NativeFileDropStarted: Codable {
    struct File: Codable {
        let fileName: String
        let fileSize: Int64
        let mimeType: String
    }

    let dropId: String
    let files: [File]
    let sceneX: Double
    let sceneY: Double
}

struct NativeFileDropFinished: Codable {
    enum Status: String, Codable {
        case handled, forwarded, ignored, failed, cancelled
    }

    let dropId: String
    let status: Status
    let message: String?
}

@MainActor
@Observable
final class NativeFileDropSession: Identifiable {
    enum Content {
        case reading
        case drawing(DroppedDrawing)
        case pdf(PDFDropInfo)
        case library(ExcalidrawLibrary)
    }

    let id = UUID()
    let webID: String?
    let targetFileID: String
    let files: [NativeFileDropStarted.File]
    var content: Content = .reading
    @ObservationIgnored var preparation: Task<Void, Never>?

    init(webID: String?, targetFileID: String, files: [NativeFileDropStarted.File] = []) {
        self.webID = webID
        self.targetFileID = targetFileID
        self.files = files
    }
}

@MainActor
extension ExcalidrawCore {
    func enableNativeFileDropNotifications() async throws {
        guard parent != nil else { return }
        _ = try await webView.callAsyncJavaScript(
            "return window.excalidrawZHelper?.setNativeFileDropNotificationsEnabled?.(true);",
            arguments: [:],
            contentWorld: .page
        )
    }

    func startNativeFileDrop(_ data: NativeFileDropStarted) {
        if nativeFileDrop?.webID == data.dropId { return }
        guard nativeFileDrop == nil, let fileID = nativeFileDropTargetID else {
            requestWebFileDropCancellation(data.dropId)
            return
        }
        nativeFileDrop = NativeFileDropSession(webID: data.dropId, targetFileID: fileID, files: data.files)
    }

    func finishNativeFileDrop(_ data: NativeFileDropFinished) {
        guard let session = nativeFileDrop, session.webID == data.dropId,
              data.status != .forwarded else { return }
        endNativeFileDrop(session)
        // The Web canvas already presents its own read errors.
        if data.status == .failed {
            logger.debug("Web file drop failed: \(data.message ?? "Unknown error")")
        }
    }

    func cancelNativeFileDrop(_ session: NativeFileDropSession, notifyWeb: Bool = true) {
        guard nativeFileDrop === session else { return }
        endNativeFileDrop(session)
        if notifyWeb, let webID = session.webID {
            requestWebFileDropCancellation(webID)
        }
    }

    func dismissNativeFileDrop(_ session: NativeFileDropSession) {
        if case .reading = session.content {
            cancelNativeFileDrop(session)
        } else {
            cancelNativeFileDrop(session, notifyWeb: false)
        }
    }

    func isCurrentNativeFileDrop(_ session: NativeFileDropSession) -> Bool {
        nativeFileDrop === session && nativeFileDropTargetID == session.targetFileID
    }

    func isAwaitingNativeFileDropPayload(_ dropID: String) -> Bool {
        guard let session = nativeFileDrop, session.webID == dropID,
              isCurrentNativeFileDrop(session), session.preparation == nil,
              case .reading = session.content else { return false }
        return true
    }

    func failNativeFileDrop(_ dropID: String, error: Error) {
        guard let session = nativeFileDrop, session.webID == dropID else { return }
        endNativeFileDrop(session)
        publishError(error)
    }

    func receiveDroppedDrawing(_ payload: OnDropExcalidrawFileMessage.Payload) {
        guard let session = nativeFileDropForPayload(payload.dropId) else { return }
        let fileID = session.targetFileID
        prepareNativeFileDrop(session, content: NativeFileDropSession.Content.drawing) {
            try DroppedDrawing(
                fileName: payload.fileName,
                fileSize: payload.fileSize,
                dataString: payload.dataString,
                targetFileID: fileID
            )
        }
    }

    func receiveDroppedPDF(_ payload: OnDropPDFMessage.OnDropPDFMessageData) {
        guard let session = nativeFileDropForPayload(payload.dropId) else { return }
        prepareNativeFileDrop(session, content: NativeFileDropSession.Content.pdf) {
            guard let data = decodeBase64(payload.base64Data),
                  Double(data.count) == payload.fileSize else { throw NativeFileDropError.invalidPDF }
#if canImport(PDFKit)
            guard PDFDocument(data: data) != nil else { throw NativeFileDropError.invalidPDF }
#endif
            return PDFDropInfo(pdfData: data, fileName: payload.fileName, sceneX: payload.sceneX, sceneY: payload.sceneY)
        }
    }

    func receiveDroppedLibrary(_ data: Data, dropID: String) {
        guard let session = nativeFileDropForPayload(dropID) else { return }
        let fileName = session.files.first?.fileName
        prepareNativeFileDrop(session, content: NativeFileDropSession.Content.library) {
            var library = try JSONDecoder().decode(OnAddLibraryMessage.self, from: data).data
            if let fileName {
                library.name = (fileName as NSString).deletingPathExtension
            }
            return library
        }
    }

    private var nativeFileDropTargetID: String? {
        guard let parent, parent.toolState.excalidrawWebCoordinator === self,
              let fileID = parent.file?.id, parent.fileState.currentActiveFile?.id == fileID,
              parent.type == .collaboration || documentSyncController.currentLoadedFileID == fileID else { return nil }
        return fileID
    }

    private func nativeFileDropForPayload(_ dropID: String?) -> NativeFileDropSession? {
        if let dropID {
            return isAwaitingNativeFileDropPayload(dropID) ? nativeFileDrop : nil
        }
        // Older Web bundles still send PDF and drawing payloads directly.
        guard nativeFileDrop == nil, let fileID = nativeFileDropTargetID else { return nil }
        let session = NativeFileDropSession(webID: nil, targetFileID: fileID)
        nativeFileDrop = session
        return session
    }

    private func prepareNativeFileDrop<Value: Sendable>(
        _ session: NativeFileDropSession,
        content: @escaping (Value) -> NativeFileDropSession.Content,
        operation: @escaping @Sendable () throws -> Value
    ) {
        session.preparation = Task { [weak self, weak session] in
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try operation()
            }
            defer { session?.preparation = nil }
            do {
                let value = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, let session,
                      isCurrentNativeFileDrop(session) else { return }
                session.content = content(value)
            } catch {
                guard !Task.isCancelled, let self, let session, nativeFileDrop === session else { return }
                endNativeFileDrop(session)
                publishError(error)
            }
        }
    }

    private func endNativeFileDrop(_ session: NativeFileDropSession) {
        session.preparation?.cancel()
        session.preparation = nil
        nativeFileDrop = nil
    }

    private func requestWebFileDropCancellation(_ dropID: String) {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "return window.excalidrawZHelper?.cancelNativeFileDrop?.(dropId);",
                arguments: ["dropId": dropID],
                contentWorld: .page
            )
        }
    }
}

enum NativeFileDropError: LocalizedError {
    case invalidPDF, targetChanged

    var errorDescription: String? {
        switch self {
            case .invalidPDF: String(localizable: .nativeFileDropInvalidPDF)
            case .targetChanged: String(localizable: .nativeFileDropTargetChanged)
        }
    }
}
