//
//  NavigateCanvasTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore

@MainActor
final class ExcalidrawCoordinatorRegistry {
    static let shared = ExcalidrawCoordinatorRegistry()

    enum CanvasTarget: String, Codable {
        case normal
        case collaboration
    }

    private final class WeakCoordinatorBox {
        weak var value: ExcalidrawCanvasView.Coordinator?

        init(_ value: ExcalidrawCanvasView.Coordinator?) {
            self.value = value
        }
    }

    private var normalCoordinatorBox = WeakCoordinatorBox(nil)
    private var collaborationCoordinatorBox = WeakCoordinatorBox(nil)
    private let normalCameraDirector = AICameraDirector()
    private let collaborationCameraDirector = AICameraDirector()

    func update(
        normal: ExcalidrawCanvasView.Coordinator?,
        collaboration: ExcalidrawCanvasView.Coordinator?
    ) {
        normalCoordinatorBox = WeakCoordinatorBox(normal)
        collaborationCoordinatorBox = WeakCoordinatorBox(collaboration)
        normalCameraDirector.coordinator = normal
        collaborationCameraDirector.coordinator = collaboration
    }

    func coordinator(for target: CanvasTarget) -> ExcalidrawCanvasView.Coordinator? {
        switch target {
            case .normal:
                normalCoordinatorBox.value
            case .collaboration:
                collaborationCoordinatorBox.value
        }
    }

    func cameraDirector(for target: CanvasTarget) -> AICameraDirector {
        switch target {
            case .normal:
                normalCameraDirector
            case .collaboration:
                collaborationCameraDirector
        }
    }

    func stopCameraDirector(for target: CanvasTarget) {
        cameraDirector(for: target).suspend()
    }
}

struct NavigateCanvasTool: Tool {
    struct NavigateCanvasContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    }

    var name: String { "navigate_canvas" }

    var description: String {
        "Navigate the Excalidraw canvas viewport by reading or changing camera position and zoom."
    }

    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "action": ParameterProperty(
                    type: "string",
                    description: "One of: get_camera, set_camera, scroll_to_center, scroll_to_element, zoom_to_fit, zoom_to_fit_elements, zoom_to."
                ),
                "elementId": ParameterProperty(
                    type: "string",
                    description: "Target element ID for scroll_to_element."
                ),
                "elementIds": ParameterProperty(
                    type: "array",
                    description: "Target element IDs for zoom_to_fit_elements."
                ),
                "camera": ParameterProperty(
                    type: "object",
                    description: "Camera patch for set_camera."
                ),
                "zoom": ParameterProperty(
                    type: "number",
                    description: "Target zoom scale for zoom_to."
                ),
                "options": ParameterProperty(
                    type: "object",
                    description: "Animation and fitting options for navigation actions."
                )
            ],
            required: ["action"]
        )
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> String {
        guard let data = input.data(using: .utf8) else {
            throw ToolError.invalidInput("Invalid input format. Expected JSON string.")
        }

        let payload: ToolInput
        do {
            payload = try JSONDecoder().decode(ToolInput.self, from: data)
        } catch {
            throw ToolError.invalidInput("Invalid input format. Expected NavigateCanvasToolInput JSON.")
        }

        guard let context else {
            throw ToolError.executionFailed("Missing NavigateCanvasContext")
        }
        let navigationContext = try context.resolve(NavigateCanvasContext.self)
        await MainActor.run {
            ExcalidrawCoordinatorRegistry.shared.stopCameraDirector(for: navigationContext.canvasTarget)
        }
        let coordinator = await MainActor.run {
            ExcalidrawCoordinatorRegistry.shared.coordinator(for: navigationContext.canvasTarget)
        }
        guard let coordinator else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

        let output = try await perform(payload, using: coordinator)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return String(data: encoded, encoding: .utf8) ?? ""
    }
}

private extension NavigateCanvasTool {
    struct ToolInput: Decodable {
        let action: Action
        let elementId: String?
        let elementIds: [String]?
        let camera: ExcalidrawCore.CameraPatch?
        let zoom: Double?
        let options: NavigationOptions?
    }

    enum Action: String, Decodable {
        case getCamera = "get_camera"
        case setCamera = "set_camera"
        case scrollToCenter = "scroll_to_center"
        case scrollToElement = "scroll_to_element"
        case zoomToFit = "zoom_to_fit"
        case zoomToFitElements = "zoom_to_fit_elements"
        case zoomTo = "zoom_to"
    }

    struct NavigationOptions: Decodable {
        let mode: ExcalidrawCore.ScrollToElementMode?
        let animate: Bool?
        let duration: Int?
        let viewportZoomFactor: Double?
        let minZoom: Double?
        let maxZoom: Double?
    }

    struct ToolOutput: Encodable {
        let ok: Bool
        let action: String
        let message: String
        let camera: ExcalidrawCore.CameraState?
    }

    @MainActor
    func perform(_ payload: ToolInput, using coordinator: ExcalidrawCanvasView.Coordinator) async throws -> ToolOutput {
        switch payload.action {
            case .getCamera:
                let camera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Fetched current camera state.",
                    camera: camera
                )

            case .setCamera:
                guard let camera = payload.camera else {
                    throw ToolError.invalidInput("Missing camera payload for set_camera.")
                }
                try await coordinator.setCamera(camera)
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Updated camera state.",
                    camera: latestCamera
                )

            case .scrollToCenter:
                try await coordinator.scrollToCenter()
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Centered the canvas.",
                    camera: latestCamera
                )

            case .scrollToElement:
                guard let elementId = payload.elementId, !elementId.isEmpty else {
                    throw ToolError.invalidInput("Missing elementId for scroll_to_element.")
                }
                try await coordinator.scrollToElement(
                    id: elementId,
                    options: .init(
                        mode: payload.options?.mode ?? .fitContent,
                        animate: payload.options?.animate ?? true,
                        duration: payload.options?.duration ?? 300,
                        viewportZoomFactor: payload.options?.viewportZoomFactor,
                        minZoom: payload.options?.minZoom,
                        maxZoom: payload.options?.maxZoom
                    )
                )
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Scrolled to element \(elementId).",
                    camera: latestCamera
                )

            case .zoomToFit:
                try await coordinator.zoomToFit(
                    options: .init(
                        animate: payload.options?.animate ?? true,
                        duration: payload.options?.duration ?? 300,
                        viewportZoomFactor: payload.options?.viewportZoomFactor ?? 0.9
                    )
                )
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Zoomed to fit visible content.",
                    camera: latestCamera
                )

            case .zoomToFitElements:
                guard let elementIds = payload.elementIds, !elementIds.isEmpty else {
                    throw ToolError.invalidInput("Missing elementIds for zoom_to_fit_elements.")
                }
                try await coordinator.zoomToFitElements(
                    ids: elementIds,
                    options: .init(
                        animate: payload.options?.animate ?? true,
                        duration: payload.options?.duration ?? 300,
                        viewportZoomFactor: payload.options?.viewportZoomFactor ?? 0.9
                    )
                )
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Zoomed to fit \(elementIds.count) elements.",
                    camera: latestCamera
                )

            case .zoomTo:
                guard let zoom = payload.zoom else {
                    throw ToolError.invalidInput("Missing zoom for zoom_to.")
                }
                try await coordinator.zoomTo(zoom)
                let latestCamera = try await coordinator.getCamera()
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Zoomed canvas to \(zoom).",
                    camera: latestCamera
                )
        }
    }
}
