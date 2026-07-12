//
//  ExcalidrawMCPUpstreamToolHandler.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/16.
//

import Foundation

struct ExcalidrawMCPUpstreamToolHandler {
    struct PublishedDiagram: Sendable {
        let checkpointID: String
    }

    private struct CameraSize: Sendable {
        let width: Double
        let height: Double
    }

    typealias ElementConverter = @Sendable ([MCPJSONValue]) async throws -> [MCPJSONValue]
    typealias PublishDiagram = @Sendable (
        _ elements: [MCPJSONValue],
        _ sourceElementCount: Int,
        _ viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?
    ) async throws -> PublishedDiagram
    typealias SaveCheckpoint = @Sendable (_ id: String, _ data: MCPJSONValue) async throws -> Void
    typealias ReadCheckpointData = @Sendable (_ id: String) async -> MCPJSONValue?
    typealias ReadCheckpointElements = @Sendable (_ id: String) async -> [MCPJSONValue]?

    var convertRawElements: ElementConverter
    var publishDiagram: PublishDiagram
    var saveCheckpointData: SaveCheckpoint
    var readCheckpointData: ReadCheckpointData
    var readCheckpointElements: ReadCheckpointElements

    func callTool(
        name: String,
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        switch name {
            case ExcalidrawMCPUpstreamContract.ToolName.readMe:
                return ExcalidrawMCPToolResult(text: ExcalidrawMCPUpstreamRecall.cheatSheet)
            case ExcalidrawMCPUpstreamContract.ToolName.createView:
                return try await createView(arguments: arguments)
            case ExcalidrawMCPUpstreamContract.ToolName.saveCheckpoint:
                return try await saveCheckpoint(arguments: arguments)
            case ExcalidrawMCPUpstreamContract.ToolName.readCheckpoint:
                return try await readCheckpoint(arguments: arguments)
            default:
                throw MCPJSONRPCError.invalidParams("Unknown tool: \(name)")
        }
    }

    private func createView(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let elementsString = arguments["elements"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("create_view requires arguments.elements.")
        }

        let inputData = Data(elementsString.utf8)
        guard inputData.count <= ExcalidrawMCPUpstreamContract.maxInputBytes else {
            return ExcalidrawMCPToolResult(
                text: "Elements input exceeds \(ExcalidrawMCPUpstreamContract.maxInputBytes) byte limit. Reduce the number of elements or use checkpoints to build incrementally.",
                isError: true
            )
        }

        let parsedElements: [MCPJSONValue]
        do {
            parsedElements = try MCPJSONValue.parseJSONArray(from: inputData)
        } catch {
            return ExcalidrawMCPToolResult(
                text: "Invalid JSON in elements. Ensure the value is a JSON array string with no comments or trailing commas.",
                isError: true
            )
        }

        let resolver = ExcalidrawMCPUpstreamElementResolver(
            loadCheckpointElements: readCheckpointElements
        )
        let resolved: ExcalidrawMCPUpstreamElementResolver.Result
        do {
            resolved = try await resolver.resolve(parsedElements)
        } catch let error as ExcalidrawMCPCheckpointNotFoundError {
            return ExcalidrawMCPToolResult(
                text: error.localizedDescription,
                isError: true
            )
        }

        let convertedElements = try await convertRawElements(resolved.elements)
        let ratioHint = Self.cameraAspectRatioHint(from: parsedElements)
        let published = try await publishDiagram(
            convertedElements,
            parsedElements.count,
            resolved.viewportUpdate
        )

        return ExcalidrawMCPToolResult(
            text: """
            Diagram received by ExcalidrawZ and applied to a file. Checkpoint id: "\(published.checkpointID)".
            If the user asks to revise this diagram, call create_view again with a restoreCheckpoint pseudo-element using that id.\(ratioHint)
            """,
            structuredContent: .object([
                "checkpointId": .string(published.checkpointID)
            ])
        )
    }

    private func saveCheckpoint(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let id = arguments["id"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("save_checkpoint requires arguments.id.")
        }
        guard let dataString = arguments["data"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("save_checkpoint requires arguments.data.")
        }
        guard Data(dataString.utf8).count <= ExcalidrawMCPUpstreamContract.maxInputBytes else {
            return ExcalidrawMCPToolResult(
                text: "Checkpoint data exceeds \(ExcalidrawMCPUpstreamContract.maxInputBytes) byte limit.",
                isError: true
            )
        }

        do {
            let data = try MCPJSONValue.parse(from: Data(dataString.utf8))
            try await saveCheckpointData(id, data)
            return ExcalidrawMCPToolResult(text: "ok")
        } catch {
            return ExcalidrawMCPToolResult(
                text: "save failed: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func readCheckpoint(
        arguments: [String: MCPJSONValue]
    ) async throws -> ExcalidrawMCPToolResult {
        guard let id = arguments["id"]?.stringValue else {
            throw MCPJSONRPCError.invalidParams("read_checkpoint requires arguments.id.")
        }
        guard let data = await readCheckpointData(id) else {
            return ExcalidrawMCPToolResult(
                text: ExcalidrawMCPCheckpointNotFoundError(id: id).localizedDescription,
                isError: true
            )
        }

        let jsonData = try data.mcpJSONData()
        let json = String(data: jsonData, encoding: .utf8) ?? "[]"
        return ExcalidrawMCPToolResult(text: json)
    }

    private static func cameraAspectRatioHint(from elements: [MCPJSONValue]) -> String {
        guard let camera = elements.compactMap(cameraSize(from:)).first(where: { camera in
            abs((camera.width / camera.height) - (4.0 / 3.0)) > 0.15
        }) else {
            return ""
        }

        return "\nTip: your cameraUpdate used \(displayNumber(camera.width))x\(displayNumber(camera.height)) — try to stick with 4:3 aspect ratio (e.g. 400x300, 800x600) in future."
    }

    private static func cameraSize(from element: MCPJSONValue) -> CameraSize? {
        guard element["type"]?.stringValue == ExcalidrawMCPUpstreamContract.PseudoElementType.cameraUpdate,
              let width = finiteNumber(element["width"]),
              let height = finiteNumber(element["height"]),
              width > 0,
              height > 0
        else {
            return nil
        }

        return CameraSize(width: width, height: height)
    }

    private static func finiteNumber(_ value: MCPJSONValue?) -> Double? {
        switch value {
            case .number(let number) where number.isFinite:
                return number
            case .string(let string):
                let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
                return number?.isFinite == true ? number : nil
            default:
                return nil
        }
    }

    private static func displayNumber(_ number: Double) -> String {
        if number.rounded(.towardZero) == number {
            return String(Int(number))
        }
        return String(number)
    }
}
