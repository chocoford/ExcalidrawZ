//
//  ExcalidrawCore+FrameHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/30.
//

import Foundation

extension ExcalidrawCore {
    @MainActor
    func createFrameFromElements(
        elementIds: [String],
        name: String? = nil,
        padding: Double? = nil,
        captureUpdate: CaptureUpdate? = nil
    ) async throws -> FrameMutationResult {
        let params = CreateFrameFromElementsParams(
            elementIds: elementIds,
            name: name,
            padding: padding,
            captureUpdate: captureUpdate
        )
        let result: FrameMutationResult = try await callFrameHelper(
            name: "createFrameFromElements",
            params: params
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "createFrameFromElements")
        return result
    }

    @MainActor
    func setElementsFrame(
        elementIds: [String],
        frameId: String?,
        captureUpdate: CaptureUpdate? = nil
    ) async throws -> FrameMutationResult {
        let params = SetElementsFrameParams(
            elementIds: elementIds,
            frameId: Nullable(frameId),
            captureUpdate: captureUpdate
        )
        let result: FrameMutationResult = try await callFrameHelper(
            name: "setElementsFrame",
            params: params
        )
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "setElementsFrame")
        return result
    }

    @MainActor
    private func callFrameHelper<Params: Encodable, Result: Decodable>(
        name: String,
        params: Params
    ) async throws -> Result {
        guard !webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let paramsJSON = try encodeJSON(params)
        let result = try await webView.callAsyncJavaScript(
            makeJavaScriptHelperCall(
                "window.excalidrawZHelper.\(name)(\(paramsJSON))"
            ),
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptHelperResult(result, as: Result.self)
    }
}
