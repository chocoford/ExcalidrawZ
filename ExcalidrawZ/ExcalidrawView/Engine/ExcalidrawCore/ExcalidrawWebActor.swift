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
        guard loadedFileID != id || force else { return nil }
        self.loadedFileID = id

        self.logger.info(
            "Load file<\(String(describing: id)), \(data.count.formatted(.byteCount(style: .file)))>, force: \(force), Thread: \(Thread().description)"
        )

        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        // `loadFileBuffer` is async on the JS side. `callAsyncJavaScript` wraps the
        // body in an async function, awaits the inner Promise, and only then resolves
        // the Swift `await` — so the caller knows Excalidraw has actually applied the
        // new scene by the time this returns.
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.loadFileBuffer(\(buf), id);",
            arguments: ["id": id],
            contentWorld: .page
        )
        return LoadFileResult(fromJS: raw)
    }
}
