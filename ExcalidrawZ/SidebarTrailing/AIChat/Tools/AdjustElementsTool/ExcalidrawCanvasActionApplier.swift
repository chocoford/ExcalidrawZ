//
//  ExcalidrawCanvasActionApplier.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import CoreGraphics
import Foundation
import LLMCore

enum ExcalidrawCanvasActionApplier {
    @MainActor
    static func apply(
        _ result: AdjustmentResult,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> CanvasApplyResult {
        let coordinator = try await readyCoordinator(for: canvasTarget)

        if result.requiresFullReplace {
            try await coordinator.replaceAllElements(result.file.elements)
        } else {
            let addedElements = result.file.elements.filter { result.createdElementIds.contains($0.id) }
            let updatedElements = result.file.elements.filter {
                result.updatedElementIds.contains($0.id) && !result.createdElementIds.contains($0.id)
            }

            if !addedElements.isEmpty {
                try await coordinator.addElements(addedElements)
            }
            if !updatedElements.isEmpty {
                let updates = try updatedElements.map { element in
                    try ExcalidrawCore.UpdateElementOperation(
                        id: element.id,
                        updates: makeElementUpdates(from: element)
                    )
                }
                try await coordinator.updateElements(updates)
            }
            if !result.deletedElementIds.isEmpty {
                try await coordinator.removeElements(ids: result.deletedElementIds)
            }
        }

        let cameraDirector = ExcalidrawCoordinatorRegistry.shared.cameraDirector(for: canvasTarget)
        let changedElementIDs = result.createdElementIds + result.updatedElementIds
        if !changedElementIDs.isEmpty || !result.deletedElementIds.isEmpty {
            try await cameraDirector.submitMutationBatch(
                elements: result.file.elements,
                changedElementIDs: changedElementIDs
            )
        }

        return try await apply(
            result.canvasActions,
            coordinator: coordinator,
            cameraDirector: cameraDirector
        )
    }

    @MainActor
    static func apply(
        _ actions: [CanvasAction],
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> CanvasApplyResult {
        let coordinator = try await readyCoordinator(for: canvasTarget)
        let cameraDirector = ExcalidrawCoordinatorRegistry.shared.cameraDirector(for: canvasTarget)
        return try await apply(
            actions,
            coordinator: coordinator,
            cameraDirector: cameraDirector
        )
    }

    @MainActor
    private static func readyCoordinator(
        for canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> ExcalidrawCanvasView.Coordinator {
        guard let coordinator = try await ExcalidrawCoordinatorRegistry.shared.resolvedCoordinator(
            for: canvasTarget
        ) else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }
        return coordinator
    }

    @MainActor
    private static func apply(
        _ actions: [CanvasAction],
        coordinator: ExcalidrawCanvasView.Coordinator,
        cameraDirector: AICameraDirector
    ) async throws -> CanvasApplyResult {
        var mermaidResults: [ExcalidrawCore.MermaidInsertResult] = []
        var latexResults: [LatexInsertResult] = []
        var skeletonResults: [ExcalidrawCore.SkeletonInsertResult] = []
        var connectResults: [ExcalidrawCore.ConnectElementsResult] = []
        var frameResults: [ExcalidrawCore.FrameMutationResult] = []
        var elementIdAliases: [String: String] = [:]

        for (index, action) in actions.enumerated() {
            do {
                switch action {
                    case .insertMermaid(let op):
                        let options = ExcalidrawCore.MermaidInsertOptions(
                            position: op.position,
                            focus: op.focus,
                            regenerateIds: op.regenerateIds,
                            mermaidConfig: op.mermaidConfig,
                            captureUpdate: op.captureUpdate
                        )
                        let insertResult = try await coordinator.insertFromMermaid(
                            op.definition,
                            options: options
                        )
                        mermaidResults.append(insertResult)
                        try await cameraDirector.submitInsertedContentBounds(makeRect(from: insertResult.bounds))

                    case .insertLatex(let op):
                        let renderedSVG = try await MathRenderService.shared.renderLatex(
                            op.latex,
                            foregroundColor: op.color
                        )
                        LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "adjust_elements")
                        let insertResult = try await coordinator.insertMathImage(
                            params: renderedSVG.mathImageParams,
                            options: .init(
                                position: .auto,
                                focus: .enabled(true),
                                captureUpdate: .immediately
                            )
                        )
                        latexResults.append(LatexInsertResult(
                            elementId: insertResult.elementId,
                            elementCount: insertResult.elementCount ?? (insertResult.elementId == nil ? 0 : 1),
                            durationMs: insertResult.durationMs,
                            usedLegacyFallback: insertResult.usedLegacyFallback
                        ))
                        if let bounds = insertResult.bounds {
                            try await cameraDirector.submitInsertedContentBounds(makeRect(from: bounds))
                        }

                    case .insertSkeleton(let op):
                        let options = ExcalidrawCore.SkeletonInsertOptions(
                            layout: op.layout,
                            layoutOptions: op.layoutOptions,
                            regenerateIds: op.regenerateIds,
                            position: op.position,
                            focus: op.focus,
                            files: op.files,
                            captureUpdate: op.captureUpdate,
                            sanitize: op.sanitize
                        )
                        let insertResult = try await coordinator.insertFromSkeleton(
                            op.skeletons,
                            options: options
                        )
                        registerElementIdAliases(
                            inputIds: op.inputElementReferenceIds,
                            outputIds: insertResult.elementIds,
                            aliases: &elementIdAliases
                        )
                        skeletonResults.append(insertResult)
                        try await cameraDirector.submitInsertedContentBounds(makeRect(from: insertResult.bounds))

                    case .connect(let op):
                        let connectResult = try await coordinator.connectElements(
                            from: elementIdAliases[op.from] ?? op.from,
                            to: elementIdAliases[op.to] ?? op.to,
                            arrow: op.arrow,
                            captureUpdate: op.captureUpdate
                        )
                        connectResults.append(connectResult)

                    case .createFrame(let op):
                        let frameResult = try await coordinator.createFrameFromElements(
                            elementIds: op.targetIds,
                            name: op.name,
                            padding: op.padding,
                            captureUpdate: op.captureUpdate
                        )
                        frameResults.append(frameResult)

                    case .setFrame(let op):
                        let frameResult = try await coordinator.setElementsFrame(
                            elementIds: op.targetIds,
                            frameId: op.frameId.value,
                            captureUpdate: op.captureUpdate
                        )
                        frameResults.append(frameResult)
                }
            } catch {
                throw CanvasActionExecutionError(
                    index: index,
                    action: canvasActionDescription(action),
                    underlying: error
                )
            }
        }

        return CanvasApplyResult(
            mermaidResults: mermaidResults,
            latexResults: latexResults,
            skeletonResults: skeletonResults,
            connectResults: connectResults,
            frameResults: frameResults
        )
    }

    private static func registerElementIdAliases(
        inputIds: [String],
        outputIds: [String],
        aliases: inout [String: String]
    ) {
        for (inputId, outputId) in zip(inputIds, outputIds) {
            aliases[inputId] = outputId
        }
    }

    private static func makeElementUpdates(from element: ExcalidrawElement) throws -> [String: ExcalidrawCore.JSONValue] {
        let data = try JSONEncoder().encode(element)
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.executionFailed("Failed to encode element updates.")
        }

        let excludedKeys: Set<String> = ["id", "seed", "version", "versionNonce", "updated", "isDeleted"]
        return try jsonObject
            .filter { !excludedKeys.contains($0.key) }
            .mapValues(makeJSONValue(from:))
    }

    private static func makeJSONValue(from value: Any) throws -> ExcalidrawCore.JSONValue {
        switch value {
            case let value as String:
                return .string(value)
            case let value as NSNumber:
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    return .bool(value.boolValue)
                }
                return .number(value.doubleValue)
            case let value as [Any]:
                return .array(try value.map(makeJSONValue(from:)))
            case let value as [String: Any]:
                return .object(try value.mapValues(makeJSONValue(from:)))
            case _ as NSNull:
                return .null
            default:
                throw ToolError.executionFailed("Unsupported update value.")
        }
    }

    private static func makeRect(from bounds: ExcalidrawCore.MermaidBounds) -> CGRect {
        CGRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func canvasActionDescription(_ action: CanvasAction) -> String {
        switch action {
            case .insertMermaid(let op):
                return "insertMermaid definition=\(preview(op.definition))"
            case .insertLatex(let op):
                var parts = ["insertLatex latex=\(preview(op.latex))"]
                if let color = op.color {
                    parts.append("color=\(color)")
                }
                return parts.joined(separator: " ")
            case .insertSkeleton(let op):
                var parts = ["insertSkeleton"]
                if let layout = op.layout {
                    parts.append("layout=\(layout)")
                }
                parts.append("skeletons=\(previewJSON(op.skeletons))")
                return parts.joined(separator: " ")
            case .connect(let op):
                return "connect from=\(op.from) to=\(op.to)"
            case .createFrame(let op):
                return "createFrame targetIds=\(op.targetIds.joined(separator: ","))"
            case .setFrame(let op):
                return "setFrame targetIds=\(op.targetIds.joined(separator: ",")) frameId=\(op.frameId)"
        }
    }

    private static func preview(_ value: String, limit: Int = 240) -> String {
        let flattened = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        if flattened.count <= limit {
            return flattened
        }
        return String(flattened.prefix(limit)) + "...(truncated)"
    }

    private static func previewJSON<T: Encodable>(_ value: T, limit: Int = 500) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "<unavailable>"
        }
        return preview(string, limit: limit)
    }

    private struct CanvasActionExecutionError: LocalizedError {
        let index: Int
        let action: String
        let underlying: Error

        var errorDescription: String? {
            let detail = AdjustElementsTool.describeExecutionError(underlying)
            return "Canvas action #\(index + 1) (\(action)) failed: \(detail)"
        }
    }
}
