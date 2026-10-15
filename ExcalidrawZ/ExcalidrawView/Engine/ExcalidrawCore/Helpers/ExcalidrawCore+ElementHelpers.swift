//
//  ExcalidrawCore+ElementHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    @MainActor
    func getSelectedElementIDs() async throws -> [String] {
        let result = try await webView.callAsyncJavaScript(
            "return window.excalidrawZHelper.getSelectedElementIds();",
            arguments: [:],
            contentWorld: .page
        )
        guard let ids = result as? [String] else {
            throw InvalidJavaScriptResult()
        }
        return ids
    }

    @MainActor
    func replaceAllElements(
        _ elements: [ExcalidrawElement],
        options: ReplaceAllElementsOptions = .init()
    ) async throws {
        guard !self.webView.isLoading else { return }
        let elementsJSON = try encodeJSON(elements)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.replaceAllElements(\(elementsJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "replaceAllElements")
    }

    @MainActor
    func replaceAllElements(
        rawElementsJSON elementsJSON: String,
        options: ReplaceAllElementsOptions = .init()
    ) async throws {
        guard !self.webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            """
            const elements = JSON.parse(elementsJSON);
            const options = JSON.parse(optionsJSON);
            window.excalidrawZHelper.replaceAllElements(elements, options);
            """,
            arguments: [
                "elementsJSON": elementsJSON,
                "optionsJSON": optionsJSON
            ],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "replaceAllElementsRaw")
    }

    @MainActor
    func createElements(
        _ elements: JSONValue,
        options: CreateElementsOptions = .init()
    ) async throws -> [JSONValue] {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let elementsJSON = try encodeJSON(elements)
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall(
                "window.excalidrawZHelper.createElements(\(elementsJSON), \(optionsJSON))"
            ),
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptHelperResult(result, as: [JSONValue].self)
    }

    @MainActor
    func addElements(_ elements: [ExcalidrawElement]) async throws {
        guard !self.webView.isLoading, !elements.isEmpty else { return }
        let elementsJSON = try encodeJSON(elements)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.addElements(\(elementsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "addElements")
    }

    @MainActor
    func updateElements(_ operations: [UpdateElementOperation]) async throws {
        guard !self.webView.isLoading, !operations.isEmpty else { return }
        let operationsJSON = try encodeJSON(operations)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.updateElements(\(operationsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "updateElements")
    }

    @MainActor
    func removeElements(ids: [String]) async throws {
        guard !self.webView.isLoading, !ids.isEmpty else { return }
        let idsJSON = try encodeJSON(ids)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.removeElements(\(idsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "removeElements")
    }
}
