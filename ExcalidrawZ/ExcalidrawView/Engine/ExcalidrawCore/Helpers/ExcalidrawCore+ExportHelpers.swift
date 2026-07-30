//
//  ExcalidrawCore+ExportHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation
import SwiftUI

enum ExcalidrawPreviewExportError: LocalizedError {
    case notReady(String)
    case timedOut(String, TimeInterval)

    var errorDescription: String? {
        switch self {
            case .notReady(let label):
                return "Preview export is not ready: \(label)"
            case .timedOut(let label, let timeout):
                return "Preview export timed out: \(label), timeout=\(String(format: "%.1f", timeout))s"
        }
    }
}

extension ExcalidrawCore {
    struct ViewportImageExportResult {
        let data: Data
        let width: Double?
        let height: Double?
        let actualScale: Double?
        let scaleClamped: Bool?
        let elementCount: Int?
        let fileCount: Int?
        let mimeType: String?
    }

    @MainActor
    func exportPNG() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.exportImage();",
            arguments: [:],
            contentWorld: .page
        )
    }

    func exportPNGData() async throws -> Data? {
        guard let file = await self.parent?.file else {
            return nil
        }
        let imageData = try await self.exportElementsToPNGData(
            elements: file.elements,
            files: file.files,
            colorScheme: .light
        )
        return imageData
    }

    func exportPDFData(
        withBackground: Bool = true,
        colorScheme: ColorScheme = .light
    ) async throws -> Data? {
        guard let file = await self.parent?.file else {
            return nil
        }
        return try await exportElementsToPDFData(
            elements: file.elements,
            files: file.files,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
    }

    func exportElementsToPNGData(
        elements: [ExcalidrawElement],
        exportingFrame: ExcalidrawFrameLikeElement? = nil,
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> Data {
        let elementsJSON = try elements.jsonStringified()
        let exportingFrameJSON = try exportingFrame?.jsonStringified() ?? "undefined"
        let filesJSON = try files?.jsonStringified() ?? "undefined"
        let script = """
        return await window.excalidrawZHelper.exportElementsToBlob(
            \(elementsJSON), \(filesJSON), {
                exportEmbedScene: \(embedScene),
                withBackground: \(withBackground),
                exportWithDarkMode: \(colorScheme == .dark),
                mimeType: 'image/png',
                exportScale: \(exportScale),
                exportingFrame: \(exportingFrameJSON)
            }
        );
        """
        let raw = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any],
              let dataString = dict["blobData"] as? String,
              let data = Data(base64Encoded: dataString) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }

    func exportViewportToPNGData(
        sceneData: Data,
        colorScheme: ColorScheme? = nil
    ) async throws -> ViewportImageExportResult {
        var scene = try makeViewportExportScene(from: sceneData)
        if let colorScheme {
            scene.appState["theme"] = colorScheme == .dark ? "dark" : "light"
        }
        let raw = try await webView.callAsyncJavaScript(
            """
            return await window.excalidrawZHelper.exportViewportToBlob({
                elements,
                appState,
                files,
            });
            """,
            arguments: [
                "elements": scene.elements,
                "appState": scene.appState,
                "files": scene.files
            ],
            contentWorld: .page
        )
        return try decodeViewportImageExportResult(raw)
    }

    func exportCurrentViewportToPNGData() async throws -> ViewportImageExportResult {
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.exportViewportToBlob();",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeViewportImageExportResult(raw)
    }

    func exportCurrentViewportToPNG() async throws -> PlatformImage {
        let result = try await exportCurrentViewportToPNGData()
        guard let image = PlatformImage(data: result.data) else {
            throw InvalidJavaScriptResult()
        }
        return image
    }

    private func decodeViewportImageExportResult(_ raw: Any?) throws -> ViewportImageExportResult {
        guard let dict = raw as? [String: Any],
              let dataString = dict["blobData"] as? String,
              let data = Data(base64Encoded: dataString) else {
            throw InvalidJavaScriptResult()
        }

        return ViewportImageExportResult(
            data: data,
            width: Self.doubleValue(fromJavaScript: dict["width"]),
            height: Self.doubleValue(fromJavaScript: dict["height"]),
            actualScale: Self.doubleValue(fromJavaScript: dict["actualScale"]),
            scaleClamped: Self.boolValue(fromJavaScript: dict["scaleClamped"]),
            elementCount: Self.intValue(fromJavaScript: dict["elementCount"]),
            fileCount: Self.intValue(fromJavaScript: dict["fileCount"]),
            mimeType: dict["mimeType"] as? String
        )
    }

    func exportViewportToPNG(
        sceneData: Data,
        colorScheme: ColorScheme? = nil
    ) async throws -> PlatformImage {
        let result = try await exportViewportToPNGData(
            sceneData: sceneData,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: result.data) else {
            throw InvalidJavaScriptResult()
        }
        return image
    }

    func exportElementsToPNG(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        withBackground: Bool = true,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> PlatformImage {
        let data = try await self.exportElementsToPNGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme,
            exportScale: exportScale
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }

    @MainActor
    var isReadyForPreviewExport: Bool {
        !isLoading && !isNavigating && isDocumentLoaded && !webView.isLoading
    }

    @MainActor
    var previewExportReadinessSummary: String {
        "isLoading=\(isLoading), isNavigating=\(isNavigating), isDocumentLoaded=\(isDocumentLoaded), webView.isLoading=\(webView.isLoading)"
    }

    @MainActor
    func exportElementsPreviewToPNG(
        elements: [ExcalidrawElement],
        exportingFrame: ExcalidrawFrameLikeElement? = nil,
        embedScene: Bool = false,
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        withBackground: Bool = true,
        colorScheme: ColorScheme,
        exportScale: Int = 1,
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws -> PlatformImage {
        guard isReadyForPreviewExport else {
            throw ExcalidrawPreviewExportError.notReady(previewExportReadinessSummary)
        }

        await PreviewExportSerialQueue.shared.acquire()
        defer {
            Task {
                await PreviewExportSerialQueue.shared.release()
            }
        }

        let data = try await withPreviewExportTimeout(
            label: "elements",
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            try await self.exportElementsToPNGData(
                elements: elements,
                exportingFrame: exportingFrame,
                files: files,
                embedScene: embedScene,
                withBackground: withBackground,
                colorScheme: colorScheme,
                exportScale: exportScale
            )
        }
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }

    @MainActor
    func exportViewportPreviewToPNG(
        sceneData: Data,
        colorScheme: ColorScheme? = nil,
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) async throws -> PlatformImage {
        guard isReadyForPreviewExport else {
            throw ExcalidrawPreviewExportError.notReady(previewExportReadinessSummary)
        }

        await PreviewExportSerialQueue.shared.acquire()
        defer {
            Task {
                await PreviewExportSerialQueue.shared.release()
            }
        }

        let result = try await withPreviewExportTimeout(
            label: "viewport",
            timeoutNanoseconds: timeoutNanoseconds
        ) {
            try await self.exportViewportToPNGData(
                sceneData: sceneData,
                colorScheme: colorScheme
            )
        }
        guard let image = PlatformImage(data: result.data) else {
            throw InvalidJavaScriptResult()
        }
        return image
    }

    func exportElementsToSVGData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let elementsJSON = try elements.jsonStringified()
        let filesJSON = try files?.jsonStringified() ?? "undefined"
        let script = """
        return await window.excalidrawZHelper.exportElementsToSvg(
            \(elementsJSON), \(filesJSON),
            \(embedScene), \(withBackground), \(colorScheme == .dark)
        );
        """
        let raw = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any],
              let svg = dict["svg"] as? String else {
            struct ExportSVGFailed: Error {}
            throw ExportSVGFailed()
        }
        let minisizedSvg = removeWidthAndHeight(from: svg).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = minisizedSvg.data(using: .utf8) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }

    func exportElementsToPDFData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let name = await parent?.file?.name ?? String(localizable: .generalUntitled)
        let svgData = try await exportElementsToSVGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        let svgURL = try getTempDirectory()
            .appendingPathComponent("\(UUID().uuidString).svg")
        try svgData.write(to: svgURL)
        return try await renderPDFData(from: svgURL, filename: name)
    }

    func exportElementsToSVG(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await exportElementsToSVGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }

    private func removeWidthAndHeight(from svgContent: String) -> String {
        let regexPattern = #"<svg([^>]*)\s+(width="[^"]*")\s*([^>]*)>"#

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let tempResult = regex.stringByReplacingMatches(
                in: svgContent,
                options: [],
                range: NSRange(location: 0, length: svgContent.utf16.count),
                withTemplate: "<svg$1 $3>"
            )

            let finalRegexPattern = #"<svg([^>]*)\s+(height="[^"]*")\s*([^>]*)>"#
            return try NSRegularExpression(pattern: finalRegexPattern, options: []).stringByReplacingMatches(
                in: tempResult,
                options: [],
                range: NSRange(location: 0, length: tempResult.utf16.count),
                withTemplate: "<svg$1 $3>"
            )
        } catch {
            logger.warning("Failed to rewrite SVG dimensions: \(error)")
            return svgContent
        }
    }

    private struct ViewportExportScene {
        let elements: Any
        var appState: [String: Any]
        let files: Any
    }

    private func makeViewportExportScene(from data: Data) throws -> ViewportExportScene {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidJavaScriptResult()
        }

        return ViewportExportScene(
            elements: object["elements"] as? [Any] ?? [],
            appState: object["appState"] as? [String: Any] ?? [:],
            files: object["files"] as? [String: Any] ?? [:]
        )
    }

    private static func doubleValue(fromJavaScript value: Any?) -> Double? {
        switch value {
            case let value as Double:
                return value
            case let value as Int:
                return Double(value)
            case let value as NSNumber:
                return value.doubleValue
            default:
                return nil
        }
    }

    private static func intValue(fromJavaScript value: Any?) -> Int? {
        switch value {
            case let value as Int:
                return value
            case let value as Double:
                return Int(value)
            case let value as NSNumber:
                return value.intValue
            default:
                return nil
        }
    }

    private static func boolValue(fromJavaScript value: Any?) -> Bool? {
        switch value {
            case let value as Bool:
                return value
            case let value as NSNumber:
                return value.boolValue
            default:
                return nil
        }
    }
}

private final class PreviewExportContinuationBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        let continuation: CheckedContinuation<Value, Error>?
        lock.lock()
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private actor PreviewExportSerialQueue {
    static let shared = PreviewExportSerialQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private extension ExcalidrawCore {
    @MainActor
    func withPreviewExportTimeout<Value>(
        label: String,
        timeoutNanoseconds: UInt64,
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let box = PreviewExportContinuationBox<Value>(continuation)
            let operationTask = Task { @MainActor in
                do {
                    let value = try await operation()
                    box.resume(with: .success(value))
                } catch {
                    box.resume(with: .failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    operationTask.cancel()
                    let timeout = TimeInterval(timeoutNanoseconds) / 1_000_000_000
                    box.resume(with: .failure(ExcalidrawPreviewExportError.timedOut(label, timeout)))
                } catch {
                    return
                }
            }
        }
    }
}
