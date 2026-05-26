//
//  ExcalidrawCore+Search.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import Foundation

/// One match returned by `excalidrawZHelper.searchElements`.
struct SearchResult: Codable, Hashable, Identifiable {
    let elementId: String
    let elementType: ElementType
    let matchIndex: Int
    let matchLength: Int
    let preview: Preview

    /// Frames and text elements are the only thing the JS side searches today.
    enum ElementType: String, Codable, Hashable {
        case text
        case frame
    }

    /// Context window around the match for the host to render.
    struct Preview: Codable, Hashable {
        let text: String
        let matchStart: Int
        let matchLength: Int
        let moreBefore: Bool
        let moreAfter: Bool
    }

    /// One element can have several matches in its text — combine both for stable identity.
    var id: String { "\(elementId)_\(matchIndex)" }
}

extension ExcalidrawCore {
    /// Run a search and (Plan B) highlight matches on the canvas in the same call.
    @MainActor
    func searchElements(
        query: String,
        highlightOnCanvas: Bool = true,
        caseSensitive: Bool = true
    ) async throws -> [SearchResult] {
        guard !self.isLoading else { return [] }
        let queryJSON = try query.jsonStringified()
        let optsJSON = try SearchOptions(
            highlightOnCanvas: highlightOnCanvas,
            caseSensitive: caseSensitive
        ).jsonStringified()
        let result = try await webView.callAsyncJavaScript(
            "return window.excalidrawZHelper.searchElements(\(queryJSON), \(optsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        guard let array = result as? [Any] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: array)
        return try JSONDecoder().decode([SearchResult].self, from: data)
    }

    @MainActor
    func clearCanvasHighlights() async throws {
        guard !self.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.clearCanvasHighlights();",
            arguments: [:],
            contentWorld: .page
        )
    }

    /// Pan + select the matched element (the JS side defaults the element to ~50% of viewport).
    @MainActor
    func focusSearchResult(elementId: String) async throws {
        guard !self.isLoading else { return }
        let elementIdJSON = try elementId.jsonStringified()
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.focusSearchResult(\(elementIdJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }
}

private struct SearchOptions: Encodable {
    let highlightOnCanvas: Bool
    let caseSensitive: Bool
}
