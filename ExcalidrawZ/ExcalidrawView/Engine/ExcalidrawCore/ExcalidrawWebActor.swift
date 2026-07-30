//
//  ExcalidrawWebActor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import Logging

private enum ExcalidrawWebActorError: LocalizedError {
    case invalidFileLoadAcknowledgement

    var errorDescription: String? {
        switch self {
            case .invalidFileLoadAcknowledgement:
                "Excalidraw returned an invalid file load acknowledgement."
        }
    }
}

// Helper: pull an Int from JS dict, tolerant of being decoded as Double.
private func jsInt(_ dict: [String: Any], _ key: String) -> Int {
    (dict[key] as? Int) ?? Int((dict[key] as? Double) ?? 0)
}

private func jsDouble(_ dict: [String: Any], _ key: String) -> Double {
    (dict[key] as? Double) ?? Double((dict[key] as? Int) ?? 0)
}

func logFileLoad(_ logger: Logger, _ message: String, level: Logger.Level = .debug) {
    switch level {
        case .trace:
            logger.trace("\(message)")
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        default:
            logger.debug("\(message)")
    }
}

func loadFileDataSummary(_ data: Data) -> String {
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let dict = object as? [String: Any]
    else {
        return "json=unreadable"
    }

    let elements = dict["elements"] as? [[String: Any]] ?? []
    let deletedCount = elements.reduce(0) { count, element in
        count + ((element["isDeleted"] as? Bool) == true ? 1 : 0)
    }
    let filesCount = (dict["files"] as? [String: Any])?.count ?? 0

    return "elements=\(elements.count), visible=\(elements.count - deletedCount), deleted=\(deletedCount), files=\(filesCount)"
}

/// Mirrors the JS-side return value from `loadFileBuffer`:
/// `{ requestId: string, fileId: string, elementCount: number, durationMs: number }`.
struct LoadFileResult {
    var requestId: String
    var fileId: String
    var elementCount: Int
    var durationMs: Double

    init?(fromJS raw: Any?) {
        guard let dict = raw as? [String: Any],
              let requestId = dict["requestId"] as? String,
              let fileId = dict["fileId"] as? String else { return nil }
        self.requestId = requestId
        self.fileId = fileId
        self.elementCount = jsInt(dict, "elementCount")
        self.durationMs = jsDouble(dict, "durationMs")
    }
}

/// JS `saveFile()` returns `{ dataString, elementCount }`.
struct SaveFileResult {
    var dataString: String
    var elementCount: Int

    init?(fromJS raw: Any?) {
        guard let dict = raw as? [String: Any],
              let dataString = dict["dataString"] as? String else { return nil }
        self.dataString = dataString
        self.elementCount = jsInt(dict, "elementCount")
    }
}

/// JS `loadLibraryItem(json)` returns `{ itemCount }`.
struct LoadLibraryItemResult {
    var itemCount: Int

    init?(fromJS raw: Any?) {
        guard let dict = raw as? [String: Any] else { return nil }
        self.itemCount = jsInt(dict, "itemCount")
    }
}

/// JS `loadImageBuffer` / `loadImage` return `{ elementCount, durationMs }`.
struct LoadImageResult {
    var elementCount: Int
    var durationMs: Double

    init?(fromJS raw: Any?) {
        guard let dict = raw as? [String: Any] else { return nil }
        self.elementCount = jsInt(dict, "elementCount")
        self.durationMs = jsDouble(dict, "durationMs")
    }
}

actor ExcalidrawWebActor {
    let logger = Logger(label: "ExcalidrawWebActor")

    weak var excalidrawCoordinator: ExcalidrawCore?

    init(coordinator: ExcalidrawCore) {
        self.excalidrawCoordinator = coordinator
    }

    var webView: ExcalidrawWebView {
        guard let excalidrawCoordinator else {
            preconditionFailure("ExcalidrawCore was released during a Web operation.")
        }
        return excalidrawCoordinator.webView
    }

    @discardableResult
    func loadFile(
        id: String,
        requestID: String,
        data: Data
    ) async throws -> LoadFileResult {
        let webView = webView
        let targetSummary = loadFileDataSummary(data)

        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        // `loadFileBuffer` is async on the JS side. `callAsyncJavaScript` wraps the
        // body in an async function, awaits the inner Promise, and only then resolves
        // the Swift `await` — so the caller knows Excalidraw has actually applied the
        // new scene by the time this returns.
        do {
            let raw = try await webView.callAsyncJavaScript(
                "return await window.excalidrawZHelper.loadFileBuffer(\(buf), id, requestID);",
                arguments: ["id": id, "requestID": requestID],
                contentWorld: .page
            )
            guard let result = LoadFileResult(fromJS: raw),
                  result.requestId == requestID,
                  result.fileId == id else {
                throw ExcalidrawWebActorError.invalidFileLoadAcknowledgement
            }
            let jsElements = String(result.elementCount)
            let durationMs = String(format: "%.1f", result.durationMs)
            logFileLoad(
                self.logger,
                "File loaded id=\(id) requestID=\(requestID) bytes=\(data.count.formatted(.byteCount(style: .file))) jsElements=\(jsElements) durationMs=\(durationMs)"
            )
            return result
        } catch {
            logFileLoad(
                self.logger,
                "File load failed id=\(id) requestID=\(requestID) target=\(targetSummary) error=\(String(describing: error))",
                level: .error
            )
            throw error
        }
    }

}
