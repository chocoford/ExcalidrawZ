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

    enum CanvasTarget: String, Codable, Sendable {
        case normal
        case collaboration
        case proposal
    }

    private final class WeakCoordinatorBox {
        weak var value: ExcalidrawCanvasView.Coordinator?

        init(_ value: ExcalidrawCanvasView.Coordinator?) {
            self.value = value
        }
    }

    private var normalCoordinatorBox = WeakCoordinatorBox(nil)
    private var collaborationCoordinatorBox = WeakCoordinatorBox(nil)
    private var proposalCoordinatorBox = WeakCoordinatorBox(nil)
    private let normalCameraDirector = AICameraDirector()
    private let collaborationCameraDirector = AICameraDirector()
    private let proposalCameraDirector = AICameraDirector()

    func update(
        normal: ExcalidrawCanvasView.Coordinator?,
        collaboration: ExcalidrawCanvasView.Coordinator?
    ) {
        normalCoordinatorBox = WeakCoordinatorBox(normal)
        collaborationCoordinatorBox = WeakCoordinatorBox(collaboration)
        normalCameraDirector.coordinator = normal
        collaborationCameraDirector.coordinator = collaboration
    }

    func updateProposal(_ proposal: ExcalidrawCanvasView.Coordinator?) {
        proposalCoordinatorBox = WeakCoordinatorBox(proposal)
        proposalCameraDirector.coordinator = proposal
    }

    func coordinator(for target: CanvasTarget) -> ExcalidrawCanvasView.Coordinator? {
        switch target {
            case .normal:
                normalCoordinatorBox.value
            case .collaboration:
                collaborationCoordinatorBox.value
            case .proposal:
                proposalCoordinatorBox.value
        }
    }

    func resolvedCoordinator(for target: CanvasTarget) async throws -> ExcalidrawCanvasView.Coordinator? {
        if target.targetsProposalCanvas {
            return try await AIProposalSandbox.readyCoordinator()
        }
        return coordinator(for: target)
    }

    func cameraDirector(for target: CanvasTarget) -> AICameraDirector {
        switch target {
            case .normal:
                normalCameraDirector
            case .collaboration:
                collaborationCameraDirector
            case .proposal:
                proposalCameraDirector
        }
    }

    func stopCameraDirector(for target: CanvasTarget) {
        cameraDirector(for: target).suspend()
    }
}

extension ExcalidrawCoordinatorRegistry.CanvasTarget {
    var targetsProposalCanvas: Bool {
        self == .proposal
    }

    var targetsUserCanvas: Bool {
        !targetsProposalCanvas
    }
}

struct NavigateCanvasTool: Tool {
    struct NavigateCanvasContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
        var currentFileID: UUID? = nil
    }

    var name: String { "navigate_canvas" }

    var displayName: String { String(localizable: .aiChatToolNavigateCanvasName) }

    var description: String {
        "Navigate the Excalidraw canvas viewport by reading or changing camera position and zoom."
    }

    var inputSchema: ToolInputSchema {
        .bundleResource(name: "NavigateCanvasToolSchema")
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

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
        guard try await LockedContentAIGuard.canToolAccess(
            canvasTarget: navigationContext.canvasTarget,
            currentFileID: navigationContext.currentFileID
        ) else {
            return LockedContentAIGuard.lockedToolResult
        }
        await MainActor.run {
            ExcalidrawCoordinatorRegistry.shared.stopCameraDirector(for: navigationContext.canvasTarget)
        }
        let coordinator = try await ExcalidrawCoordinatorRegistry.shared.resolvedCoordinator(
            for: navigationContext.canvasTarget
        )
        guard let coordinator else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

        let output = try await perform(payload, using: coordinator)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return .text(String(data: encoded, encoding: .utf8) ?? "")
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
                let latestCamera = try await cameraAfterMutation(
                    using: coordinator,
                    expected: camera
                )
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Updated camera state.",
                    camera: latestCamera
                )

            case .scrollToCenter:
                let beforeCamera = try await coordinator.getCamera()
                try await coordinator.scrollToCenter()
                let latestCamera = try await cameraAfterComputedMutation(
                    using: coordinator,
                    before: beforeCamera,
                    animate: payload.options?.animate ?? true,
                    duration: payload.options?.duration ?? 300
                )
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
                let animate = payload.options?.animate ?? true
                let duration = payload.options?.duration ?? 300
                let beforeCamera = try await coordinator.getCamera()
                try await coordinator.scrollToElement(
                    id: elementId,
                    options: .init(
                        mode: payload.options?.mode ?? .fitContent,
                        animate: animate,
                        duration: duration,
                        viewportZoomFactor: payload.options?.viewportZoomFactor,
                        minZoom: payload.options?.minZoom,
                        maxZoom: payload.options?.maxZoom
                    )
                )
                let latestCamera = try await cameraAfterComputedMutation(
                    using: coordinator,
                    before: beforeCamera,
                    animate: animate,
                    duration: duration
                )
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Scrolled to element \(elementId).",
                    camera: latestCamera
                )

            case .zoomToFit:
                let animate = payload.options?.animate ?? true
                let duration = payload.options?.duration ?? 300
                let beforeCamera = try await coordinator.getCamera()
                try await coordinator.zoomToFit(
                    options: .init(
                        animate: animate,
                        duration: duration,
                        viewportZoomFactor: payload.options?.viewportZoomFactor ?? 0.9
                    )
                )
                let latestCamera = try await cameraAfterComputedMutation(
                    using: coordinator,
                    before: beforeCamera,
                    animate: animate,
                    duration: duration
                )
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
                let animate = payload.options?.animate ?? true
                let duration = payload.options?.duration ?? 300
                let beforeCamera = try await coordinator.getCamera()
                try await coordinator.zoomToFitElements(
                    ids: elementIds,
                    options: .init(
                        animate: animate,
                        duration: duration,
                        viewportZoomFactor: payload.options?.viewportZoomFactor ?? 0.9
                    )
                )
                let latestCamera = try await cameraAfterComputedMutation(
                    using: coordinator,
                    before: beforeCamera,
                    animate: animate,
                    duration: duration
                )
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
                let latestCamera = try await cameraAfterMutation(
                    using: coordinator,
                    expected: .init(zoom: zoom)
                )
                return ToolOutput(
                    ok: true,
                    action: payload.action.rawValue,
                    message: "Zoomed canvas to \(zoom).",
                    camera: latestCamera
                )
        }
    }

    @MainActor
    func cameraAfterMutation(
        using coordinator: ExcalidrawCanvasView.Coordinator,
        expected: ExcalidrawCore.CameraPatch
    ) async throws -> ExcalidrawCore.CameraState {
        let deadline = Date().addingTimeInterval(0.6)
        var latestCamera = try await coordinator.getCamera()
        while Date() < deadline {
            if camera(latestCamera, matches: expected) {
                return latestCamera
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            latestCamera = try await coordinator.getCamera()
        }
        return latestCamera
    }

    @MainActor
    func cameraAfterComputedMutation(
        using coordinator: ExcalidrawCanvasView.Coordinator,
        before beforeCamera: ExcalidrawCore.CameraState,
        animate: Bool,
        duration: Int
    ) async throws -> ExcalidrawCore.CameraState {
        let animationSeconds = animate ? max(Double(duration), 0) / 1000 : 0
        let timeout = max(0.35, min(animationSeconds + 0.4, 2.0))
        let deadline = Date().addingTimeInterval(timeout)
        var latestCamera = try await coordinator.getCamera()
        var previousCamera = latestCamera
        var stableSampleCount = 0

        while Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
            latestCamera = try await coordinator.getCamera()

            if camera(latestCamera, approximatelyMatches: previousCamera) {
                stableSampleCount += 1
            } else {
                stableSampleCount = 0
            }

            if stableSampleCount >= 2,
               !camera(latestCamera, approximatelyMatches: beforeCamera) {
                return latestCamera
            }

            previousCamera = latestCamera
        }

        return latestCamera
    }

    func camera(_ camera: ExcalidrawCore.CameraState, matches patch: ExcalidrawCore.CameraPatch) -> Bool {
        if let scrollX = patch.scrollX, !approximatelyEqual(camera.scrollX, scrollX) {
            return false
        }
        if let scrollY = patch.scrollY, !approximatelyEqual(camera.scrollY, scrollY) {
            return false
        }
        if let zoom = patch.zoom, !approximatelyEqual(camera.zoom, zoom) {
            return false
        }
        return true
    }

    func camera(
        _ lhs: ExcalidrawCore.CameraState,
        approximatelyMatches rhs: ExcalidrawCore.CameraState
    ) -> Bool {
        approximatelyEqual(lhs.scrollX, rhs.scrollX) &&
        approximatelyEqual(lhs.scrollY, rhs.scrollY) &&
        approximatelyEqual(lhs.zoom, rhs.zoom)
    }

    func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
