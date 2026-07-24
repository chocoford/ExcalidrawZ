//
//  ExcalidrawMCPUpstreamElementResolver.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/15.
//

import Foundation

struct ExcalidrawMCPCheckpointNotFoundError: LocalizedError, Sendable {
    let id: String

    var errorDescription: String? {
        "Checkpoint \"\(id)\" not found — it may have expired or never existed. Please recreate the diagram from scratch."
    }
}

struct ExcalidrawMCPUpstreamViewportUpdate: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ExcalidrawMCPUpstreamElementResolver {
    struct Result: Sendable {
        let elements: [MCPJSONValue]
        let viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?
    }

    private struct ExtractedElements: Sendable {
        let drawElements: [MCPJSONValue]
        let restoreCheckpointID: String?
        let deleteIDs: Set<String>
        let viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?
    }

    var loadCheckpointElements: @Sendable (String) async -> [MCPJSONValue]?

    func resolve(_ parsedElements: [MCPJSONValue]) async throws -> Result {
        let extracted = Self.extractViewportAndElements(parsedElements)

        let resolvedElements: [MCPJSONValue]
        if let restoreCheckpointID = extracted.restoreCheckpointID {
            guard let checkpointElements = await loadCheckpointElements(restoreCheckpointID) else {
                throw ExcalidrawMCPCheckpointNotFoundError(id: restoreCheckpointID)
            }

            let base = Self.extractViewportAndElements(checkpointElements).drawElements
            let filteredBase = Self.filterDeletedElements(
                base,
                deleteIDs: extracted.deleteIDs
            )
            resolvedElements = filteredBase + extracted.drawElements
        } else {
            resolvedElements = extracted.drawElements
        }

        return Result(
            elements: resolvedElements,
            viewportUpdate: extracted.viewportUpdate
        )
    }

    private static func extractViewportAndElements(_ elements: [MCPJSONValue]) -> ExtractedElements {
        var restoreCheckpointID: String?
        var deleteIDs: Set<String> = []
        var drawElements: [MCPJSONValue] = []
        var viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?

        for element in elements {
            switch element["type"]?.stringValue {
                case ExcalidrawMCPUpstreamContract.PseudoElementType.cameraUpdate:
                    viewportUpdate = Self.viewportUpdate(from: element) ?? viewportUpdate
                    continue
                case ExcalidrawMCPUpstreamContract.PseudoElementType.restoreCheckpoint:
                    restoreCheckpointID = Self.nonEmptyString(element["id"])
                case ExcalidrawMCPUpstreamContract.PseudoElementType.delete:
                    deleteIDs.formUnion(Self.deleteIDs(from: element))
                default:
                    drawElements.append(element)
            }
        }

        if !deleteIDs.isEmpty {
            drawElements = drawElements.map {
                Self.elementHiddenForInlineDelete($0, deleteIDs: deleteIDs)
            }
        }

        return ExtractedElements(
            drawElements: drawElements,
            restoreCheckpointID: restoreCheckpointID,
            deleteIDs: deleteIDs,
            viewportUpdate: viewportUpdate
        )
    }

    private static func viewportUpdate(from element: MCPJSONValue) -> ExcalidrawMCPUpstreamViewportUpdate? {
        guard let x = finiteNumber(element["x"]),
              let y = finiteNumber(element["y"]),
              let width = finiteNumber(element["width"]),
              let height = finiteNumber(element["height"]),
              width > 0,
              height > 0
        else {
            return nil
        }

        return ExcalidrawMCPUpstreamViewportUpdate(
            x: x,
            y: y,
            width: width,
            height: height
        )
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

    private static func filterDeletedElements(
        _ elements: [MCPJSONValue],
        deleteIDs: Set<String>
    ) -> [MCPJSONValue] {
        guard !deleteIDs.isEmpty else { return elements }
        return elements.filter { element in
            !shouldHideInlineDeletedElement(element, deleteIDs: deleteIDs)
        }
    }

    private static func shouldHideInlineDeletedElement(
        _ element: MCPJSONValue,
        deleteIDs: Set<String>
    ) -> Bool {
        let id = element["id"]?.stringValue
        let containerID = element["containerId"]?.stringValue
        return deleteIDs.contains(id ?? "") || deleteIDs.contains(containerID ?? "")
    }

    private static func elementHiddenForInlineDelete(
        _ element: MCPJSONValue,
        deleteIDs: Set<String>
    ) -> MCPJSONValue {
        guard shouldHideInlineDeletedElement(element, deleteIDs: deleteIDs),
              var object = element.objectValue
        else {
            return element
        }

        // Upstream uses opacity 1, not 0, because Excalidraw treats 0 as unset.
        object["opacity"] = .number(1)
        return .object(object)
    }

    private static func deleteIDs(from element: MCPJSONValue) -> [String] {
        guard element["type"]?.stringValue == ExcalidrawMCPUpstreamContract.PseudoElementType.delete else {
            return []
        }
        if let ids = element["ids"]?.arrayValue {
            return ids.compactMap(Self.stringLikeValue)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let raw = Self.stringLikeValue(element["ids"]) ?? Self.stringLikeValue(element["id"]) ?? ""
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stringLikeValue(_ value: MCPJSONValue?) -> String? {
        switch value {
            case .string(let string):
                return string
            case .number(let number) where number.isFinite:
                return number.rounded(.towardZero) == number
                    ? String(Int(number))
                    : String(number)
            default:
                return nil
        }
    }

    private static func nonEmptyString(_ value: MCPJSONValue?) -> String? {
        guard let string = value?.stringValue, !string.isEmpty else {
            return nil
        }
        return string
    }
}
