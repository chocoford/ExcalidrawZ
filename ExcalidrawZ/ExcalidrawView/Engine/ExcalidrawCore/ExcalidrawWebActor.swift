//
//  ExcalidrawWebActor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import Logging

// Helper: pull an Int from JS dict, tolerant of being decoded as Double.
private func jsInt(_ dict: [String: Any], _ key: String) -> Int {
    (dict[key] as? Int) ?? Int((dict[key] as? Double) ?? 0)
}

private func jsDouble(_ dict: [String: Any], _ key: String) -> Double {
    (dict[key] as? Double) ?? Double((dict[key] as? Int) ?? 0)
}

func logLoadFileDiag(_ logger: Logger, _ message: String, level: Logger.Level = .info) {
    switch level {
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        default:
            logger.info("\(message)")
    }
}

private func loadFileDataSummary(_ data: Data) -> String {
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

/// Mirrors the JS-side return value from `loadFileBuffer`/`loadFileString`:
/// `{ fileId?: string, elementCount: number, durationMs: number }`.
/// `fileId` is only populated by `loadFileBuffer`.
struct LoadFileResult {
    var fileId: String?
    var elementCount: Int
    var durationMs: Double

    init?(fromJS raw: Any?) {
        guard let dict = raw as? [String: Any] else { return nil }
        self.fileId = dict["fileId"] as? String
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

    var excalidrawCoordinator: ExcalidrawCore

    init(coordinator: ExcalidrawCore) {
        self.excalidrawCoordinator = coordinator
    }

    var loadedFileID: String?
    var webView: ExcalidrawWebView { excalidrawCoordinator.webView }

    @discardableResult
    func loadFile(id: String, data: Data, force: Bool = false) async throws -> LoadFileResult? {
        let webView = webView
        let targetSummary = loadFileDataSummary(data)
        guard loadedFileID != id || force else {
            logLoadFileDiag(
                self.logger,
                "[LoadFileDiag] skip id=\(id) loadedFileID=\(self.loadedFileID ?? "nil") force=\(force) target=\(targetSummary)"
            )
            return nil
        }

        logLoadFileDiag(
            self.logger,
            "[LoadFileDiag] start id=\(id) bytes=\(data.count.formatted(.byteCount(style: .file))) force=\(force) loadedFileID=\(self.loadedFileID ?? "nil") target=\(targetSummary)"
        )

        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        // `loadFileBuffer` is async on the JS side. `callAsyncJavaScript` wraps the
        // body in an async function, awaits the inner Promise, and only then resolves
        // the Swift `await` — so the caller knows Excalidraw has actually applied the
        // new scene by the time this returns.
        do {
            let raw = try await webView.callAsyncJavaScript(
                "return await window.excalidrawZHelper.loadFileBuffer(\(buf), id);",
                arguments: ["id": id],
                contentWorld: .page
            )
            self.loadedFileID = id
            let result = LoadFileResult(fromJS: raw)
            let resultFileID = result?.fileId ?? "nil"
            let jsElements = result.map { String($0.elementCount) } ?? "nil"
            let durationMs = result.map { String(format: "%.1f", $0.durationMs) } ?? "nil"
            logLoadFileDiag(
                self.logger,
                "[LoadFileDiag] success id=\(id) resultFileId=\(resultFileID) jsElements=\(jsElements) durationMs=\(durationMs)"
            )
            return result
        } catch {
            // JS-side `loadFileBuffer` has a watchdog timeout that fires
            // when its `onChange` listener can't tell the post-load scene
            // apart from the pre-load one: it compares element counts +
            // ID sets and bails the resolve if they match. The most
            // common trigger is loading an empty file onto an empty
            // canvas — both scenes have 0 elements, so the watchdog
            // can't disambiguate "new state arrived" from "old state
            // re-emitted" and times out.
            //
            // Crucially, `excalidrawAPI.updateScene` was called
            // synchronously *before* the watchdog started waiting, so
            // by the time the timeout fires the scene IS at the new
            // file's state. Treating the timeout as success — and thus
            // committing `loadedFileID` — lets `onStateChanged`'s
            // `loadedFileID == currentFileID` gate pass for subsequent
            // edits. Otherwise every JS-side state update (including
            // user draws and AI tool mutations) gets dropped for the
            // lifetime of the editor on this file.
            if Self.isLoadTimeoutError(error) {
                logLoadFileDiag(
                    self.logger,
                    "[LoadFileDiag] timeout-suppressed id=\(id) target=\(targetSummary) error=\(String(describing: error))",
                    level: .warning
                )
                self.loadedFileID = id
                return nil
            }
            logLoadFileDiag(
                self.logger,
                "[LoadFileDiag] failure id=\(id) target=\(targetSummary) error=\(String(describing: error))",
                level: .error
            )
            throw error
        }
    }

    /// Match the JS `loadFileBuffer` watchdog timeout — a `WKErrorDomain`
    /// code 4 ("A JavaScript exception occurred") whose embedded message
    /// starts with our specific timeout string. Anchored on the literal
    /// JS error string we throw, so unrelated JS exceptions (syntax
    /// errors, undefined helpers, etc.) still surface to the caller.
    private static func isLoadTimeoutError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "WKErrorDomain", nsError.code == 4 else {
            return false
        }
        let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String
        return message?.contains("load timed out") == true
    }
}
