import Foundation
import WebKit

extension ExcalidrawCore {
    struct NativePasteRequest: Codable, Sendable {
        struct File: Codable, Sendable {
            let name: String
            let mimeType: String
            let size: Int
        }

        let requestId: String
        let reason: String
        let types: [String]
        let files: [File]
    }

    struct NativePasteCompletion: Encodable, Sendable {
        enum Status: String, Encodable, Sendable {
            case success, unhandled, error
        }

        let requestId: String
        let status: Status
        var images: [NativePasteImageConverter.Image]? = nil
        var message: String? = nil
    }

    @MainActor
    func enableNativePaste() async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            const helper = window.excalidrawZHelper;
            if (typeof helper?.setNativePasteEnabled === 'function' &&
                typeof helper?.completeNativePaste === 'function') {
                helper.setNativePasteEnabled(true);
            }
            """,
            arguments: [:], contentWorld: .page
        )
    }

    @MainActor
    func completeNativePaste(_ completion: NativePasteCompletion) async throws {
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(completion))
        let response = try await webView.callAsyncJavaScript(
            "return window.excalidrawZHelper?.completeNativePaste?.(completion);",
            arguments: ["completion": payload], contentWorld: .page
        )
        if let acknowledgement = response as? [String: Any],
           acknowledgement["accepted"] as? Bool == false {
            logger.debug("Native paste receipt rejected: \(acknowledgement["reason"] as? String ?? "unknown")")
        }
    }
}

@MainActor
final class ExcalidrawNativePasteCoordinator {
    private weak var core: ExcalidrawCore?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var receivedRequestIDs: Set<String> = []

    init(core: ExcalidrawCore) {
        self.core = core
    }

    func request(_ request: ExcalidrawCore.NativePasteRequest) {
        guard receivedRequestIDs.insert(request.requestId).inserted else { return }

        let supportsRequest = ["empty-files", "unsupported-image"].contains(request.reason)
            && request.files.allSatisfy {
                NativePasteboard.isImageFile(name: $0.name, mimeType: $0.mimeType)
            }
        let sources = supportsRequest ? NativePasteboard.readImages() : []
        let canHandle = supportsRequest
            && (request.files.isEmpty || request.files.count == sources.count)

        tasks[request.requestId] = Task { [weak self] in
            let completion: ExcalidrawCore.NativePasteCompletion
            if !canHandle || sources.isEmpty {
                completion = .init(requestId: request.requestId, status: .unhandled)
            } else {
                let conversion = Task.detached(priority: .userInitiated) {
                    try NativePasteImageConverter.convert(sources)
                }
                do {
                    let images = try await withTaskCancellationHandler {
                        try await conversion.value
                    } onCancel: {
                        conversion.cancel()
                    }
                    completion = .init(requestId: request.requestId, status: .success, images: images)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.core?.logger.warning("Native paste image conversion failed: \(error)")
                    completion = .init(
                        requestId: request.requestId, status: .error,
                        message: NativePasteImageConverter.failureMessage
                    )
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.tasks[request.requestId] = nil
            do {
                try await self.core?.completeNativePaste(completion)
            } catch {
                self.core?.logger.warning("Failed to deliver native paste receipt: \(error)")
            }
        }
    }

    func invalidate() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        receivedRequestIDs.removeAll()
    }
}
