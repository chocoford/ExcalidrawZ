//
//  ExcalidrawCore+ViewportHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    @MainActor
    func getCamera() async throws -> CameraState {
        guard !self.webView.isLoading else {
            return cameraState
        }
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(window.excalidrawZHelper.getCamera());",
            arguments: [:],
            contentWorld: .page
        )
        let camera = try decodeJavaScriptResult(result, as: CameraState.self)
        updateCameraState(camera)
        return camera
    }

    @MainActor
    func getViewportCenter() async throws -> CanvasPoint {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let result = try await webView.callAsyncJavaScript(
            """
            const api = window.excalidrawZHelper?._api;
            if (!api) {
                throw new Error("getViewportCenter: excalidrawAPI not ready");
            }
            const appState = api.getAppState();
            const zoom = appState.zoom?.value ?? 1;
            return JSON.stringify({
                x: appState.width / 2 / zoom - appState.scrollX,
                y: appState.height / 2 / zoom - appState.scrollY,
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: CanvasPoint.self)
    }

    @MainActor
    func setCamera(_ camera: CameraPatch) async throws {
        guard !self.webView.isLoading else { return }
        let payload = try encodeJSON(camera)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.setCamera(\(payload));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    @discardableResult
    func setViewportFrame(_ frame: ViewportFrame) async throws -> CameraState {
        guard !self.webView.isLoading else { return cameraState }
        let payload = try encodeJSON(frame)
        let result = try await webView.callAsyncJavaScript(
            """
            const frame = \(payload);
            const helper = window.excalidrawZHelper;
            const api = helper?._api;
            if (!helper || !api) {
                throw new Error("setViewportFrame: excalidrawAPI not ready");
            }

            const appState = api.getAppState();
            const viewportWidth = Number(appState.width) || window.innerWidth || frame.width;
            const viewportHeight = Number(appState.height) || window.innerHeight || frame.height;
            const frameWidth = Math.max(Math.abs(Number(frame.width) || viewportWidth), 1);
            const frameHeight = Math.max(Math.abs(Number(frame.height) || viewportHeight), 1);
            const zoom = Math.min(viewportWidth / frameWidth, viewportHeight / frameHeight);
            const centerX = Number(frame.x || 0) + frameWidth / 2;
            const centerY = Number(frame.y || 0) + frameHeight / 2;
            const camera = {
                scrollX: viewportWidth / 2 / zoom - centerX,
                scrollY: viewportHeight / 2 / zoom - centerY,
                zoom,
            };

            helper.setCamera(camera);
            return JSON.stringify(helper.getCamera());
            """,
            arguments: [:],
            contentWorld: .page
        )
        let camera = try decodeJavaScriptResult(result, as: CameraState.self)
        updateCameraState(camera)
        return camera
    }

    @MainActor
    func scrollToCenter() async throws {
        guard !self.webView.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.scrollToCenter();",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func scrollToElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.scrollToElement('\(id)', \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomToFit(options: ZoomToFitOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomToFit(\(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomToFitElements(ids: [String], options: ZoomToFitOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let idsJSON = try encodeJSON(ids)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomToFitElements(\(idsJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomTo(_ scale: Double) async throws {
        guard !self.webView.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomTo(\(scale));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func revealElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        var mergedOptions = options
        mergedOptions.mode = .fitContent
        try await scrollToElement(id: id, options: mergedOptions)
    }

    @MainActor
    func focusElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        var mergedOptions = options
        mergedOptions.mode = .fitViewport
        if mergedOptions.viewportZoomFactor == nil {
            mergedOptions.viewportZoomFactor = 0.6
        }
        try await scrollToElement(id: id, options: mergedOptions)
    }
}
