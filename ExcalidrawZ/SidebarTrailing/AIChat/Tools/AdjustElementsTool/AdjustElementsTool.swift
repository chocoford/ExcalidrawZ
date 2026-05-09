//
//  AdjustElementsTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore

struct AdjustElementsTool: Tool {
    struct AdjustElementsContext: ToolContext {
        var currentFileData: Data?
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    }

    var name: String { "adjust_elements" }

    var displayName: String { "Adjust Canvas" }

    var description: String {
        """
        Apply a batch of safe Excalidraw edits using a small DSL.

        Supported element types: text, rectangle, ellipse, diamond, line, arrow.

        Common usage:
        • Shapes (rectangle/ellipse/diamond): x/y + width/height, optional stylePreset and/or style.
        • Text: text/label content; pass `containerId` to embed it as a label inside an existing shape (auto-centered).
        • Lines: `endX`/`endY` for endpoint, or width/height as deltas.
        • Arrows: `fromId` and/or `toId` to bind endpoints to existing shapes (centered, edge-orbit). Otherwise use `endX`/`endY`. Optional `arrowhead`, `elbowed`.

        Styling:
        • `stylePreset` (`default` / `accent` / `note`) for quick consistent looks.
        • `style` for per-field overrides — `strokeColor`, `backgroundColor` (hex or `transparent`), `strokeWidth`, `roughness` (0/1/2), `opacity` (0–100), `fontSize`, `fontFamily`, `textAlign`, `verticalAlign`. Layered on top of `stylePreset` when both supplied. Use `style` whenever the user asks for specific colors or sizes.

        Higher-level layout:
        • `wrap`: give `targetIds`; the app computes their bounding box and adds a rectangle/ellipse/diamond around them. Optional `padding`, `stylePreset`/`style`, `label`.

        Ops: `add` / `update` (patch text/bounds/stylePreset/style/containerId) / `move` (dx/dy) / `resize` (width/height absolute or dw/dh delta) / `delete` / `wrap`.
        """
    }

    /// Schema lives in a JSON file shipped with the bundle. The shape uses
    /// `oneOf` over op variants and other JSON Schema features that don't map
    /// cleanly onto the flat `ToolParameters` builder, so we keep it as JSON
    /// and let `.bundleResource` load it at resolve time.
    var inputSchema: ToolInputSchema {
        .bundleResource(name: "AdjustElementsToolSchema")
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        guard let data = input.data(using: .utf8) else {
            throw ToolError.invalidInput("Invalid input format. Expected JSON string.")
        }

        let payload: ToolInput
        do {
            payload = try JSONDecoder().decode(ToolInput.self, from: data)
        } catch {
            throw ToolError.invalidInput("Invalid input format. Expected AdjustElementsToolInput JSON.")
        }

        guard let context else {
            throw ToolError.executionFailed("Missing AdjustElementsContext")
        }
        let adjustContext = try context.resolve(AdjustElementsContext.self)
        guard let currentFileData = adjustContext.currentFileData else {
            throw ToolError.executionFailed("Missing current file data")
        }

        let currentFile: ExcalidrawFile
        do {
            currentFile = try ExcalidrawFile(data: currentFileData)
        } catch {
            throw ToolError.executionFailed("Invalid Excalidraw file data.")
        }

        let middleware = AdjustElementsMiddleware(file: currentFile)
        let result = try middleware.apply(payload)

        if !(payload.dryRun ?? false) {
            try await apply(result, canvasTarget: adjustContext.canvasTarget)
        }

        let output = ToolOutput(
            ok: true,
            version: payload.version ?? "1",
            dryRun: payload.dryRun ?? false,
            opCount: payload.ops.count,
            opCounts: result.opCounts
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return .text(String(data: encoded, encoding: .utf8) ?? "")
    }
}

private extension AdjustElementsTool {
    @MainActor
    func apply(
        _ result: AdjustmentResult,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws {
        guard let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget) else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

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

        try await ExcalidrawCoordinatorRegistry.shared.cameraDirector(for: canvasTarget).submitMutationBatch(
            elements: result.file.elements,
            changedElementIDs: result.createdElementIds + result.updatedElementIds
        )
    }

    func makeElementUpdates(from element: ExcalidrawElement) throws -> [String: ExcalidrawCore.JSONValue] {
        let data = try JSONEncoder().encode(element)
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.executionFailed("Failed to encode element updates.")
        }

        let excludedKeys: Set<String> = ["id", "seed", "version", "versionNonce", "updated", "isDeleted"]
        return try jsonObject
            .filter { !excludedKeys.contains($0.key) }
            .mapValues(Self.makeJSONValue(from:))
    }

    static func makeJSONValue(from value: Any) throws -> ExcalidrawCore.JSONValue {
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
}

private struct ToolOutput: Encodable {
    let ok: Bool
    let version: String
    let dryRun: Bool
    let opCount: Int
    let opCounts: [String: Int]
}

private struct ToolInput: Decodable {
    let version: String?
    let dryRun: Bool?
    let ops: [Operation]
}

private enum Operation: Decodable {
    case add(AddOp)
    case update(UpdateOp)
    case move(MoveOp)
    case resize(ResizeOp)
    case delete(DeleteOp)
    case wrap(WrapOp)

    var kind: String {
        switch self {
            case .add: return "add"
            case .update: return "update"
            case .move: return "move"
            case .resize: return "resize"
            case .delete: return "delete"
            case .wrap: return "wrap"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case op
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
            case "add":
                self = .add(try AddOp(from: decoder))
            case "update":
                self = .update(try UpdateOp(from: decoder))
            case "move":
                self = .move(try MoveOp(from: decoder))
            case "resize":
                self = .resize(try ResizeOp(from: decoder))
            case "delete":
                self = .delete(try DeleteOp(from: decoder))
            case "wrap":
                self = .wrap(try WrapOp(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .op,
                    in: container,
                    debugDescription: "Unsupported op: \(op)"
                )
        }
    }
}

private struct AddOp: Decodable {
    let op: String
    let element: ElementSkeleton
    let place: PlaceHint?
}

private struct UpdateOp: Decodable {
    let op: String
    let id: String
    let patch: ElementPatch
}

private struct MoveOp: Decodable {
    let op: String
    let id: String
    let dx: Double
    let dy: Double
}

private struct ResizeOp: Decodable {
    let op: String
    let id: String
    let width: Double?
    let height: Double?
    let dw: Double?
    let dh: Double?
    let anchor: String?
}

private struct DeleteOp: Decodable {
    let op: String
    let id: String
}

private struct WrapOp: Decodable {
    let op: String
    let targetIds: [String]
    let shape: String?
    let padding: Double?
    let stylePreset: String?
    let style: StylePatch?
    let label: String?
    let labelPosition: String?
}

private struct ElementSkeleton: Decodable {
    let id: String?
    let type: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let text: String?
    let label: String?
    let endX: Double?
    let endY: Double?
    let fromId: String?
    let toId: String?
    let arrowhead: String?
    let elbowed: Bool?
    let containerId: String?
    let stylePreset: String?
    let style: StylePatch?
}

private struct PlaceHint: Decodable {
    let relativeToId: String
    let position: String
    let gap: Double?
}

private struct ElementPatch: Decodable {
    let text: String?
    let label: String?
    let bounds: BoundsPatch?
    let stylePreset: String?
    let style: StylePatch?
    let locked: Bool?
    let link: String?
    /// `nil` = no change. `.null` = unbind. `.value(id)` = bind text to that container.
    let containerId: Nullable<String>?
}

private struct BoundsPatch: Decodable {
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
}

private struct StylePatch: Decodable {
    let strokeColor: String?
    let backgroundColor: String?
    let strokeWidth: Double?
    let roughness: Double?
    let opacity: Double?
    let fontSize: Double?
    let fontFamily: Double?
    let textAlign: String?
    let verticalAlign: String?
}

private struct AdjustmentResult {
    let file: ExcalidrawFile
    let opCounts: [String: Int]
    let createdElementIds: [String]
    let updatedElementIds: [String]
    let deletedElementIds: [String]
    let requiresFullReplace: Bool
}

/// Result of hydrating an `add` op: the new element plus any boundElements
/// entries that need to be appended to existing parent elements (text→container,
/// arrow→source/target shapes).
private struct AddOpResult {
    struct ParentBinding {
        let parentID: String
        let entry: ExcalidrawBoundElement
    }
    let element: ExcalidrawElement
    let parentBindings: [ParentBinding]
}

/// Result of patching an element: the full updated elements array plus the IDs
/// of any other elements that got mutated as a side effect (eg the previous
/// container losing its `boundElements` entry when text rebinds).
private struct PatchResult {
    let elements: [ExcalidrawElement]
    let touchedParentIDs: [String]
}

/// Result of hydrating a `wrap` op. Wrappers are inserted before the first
/// target so the surrounding shape sits behind the wrapped elements.
private struct WrapOpResult {
    let elements: [ExcalidrawElement]
    let insertionIndex: Int
}

private struct AdjustElementsMiddleware {
    private let file: ExcalidrawFile

    init(file: ExcalidrawFile) {
        self.file = file
    }

    func apply(_ payload: ToolInput) throws -> AdjustmentResult {
        var elements = file.elements
        var createdElementIds: [String] = []
        var updatedElementIds: [String] = []
        var deletedElementIds: [String] = []
        var requiresFullReplace = false

        let opCounts = payload.ops.reduce(into: [String: Int]()) { partial, op in
            partial[op.kind, default: 0] += 1
        }

        for op in payload.ops {
            switch op {
                case .add(let addOp):
                    let result = try hydrateAddOp(addOp, existingElements: elements)
                    elements.append(result.element)
                    createdElementIds.append(result.element.id)
                    // Apply parent boundElements mutations (text→container, arrow→endpoints).
                    for binding in result.parentBindings {
                        let parentIdx = try indexOfElement(binding.parentID, in: elements)
                        elements[parentIdx] = appendBoundElement(elements[parentIdx], entry: binding.entry)
                        if !updatedElementIds.contains(binding.parentID) {
                            updatedElementIds.append(binding.parentID)
                        }
                    }

                case .update(let updateOp):
                    let result = try patchElement(
                        elements,
                        targetIndex: try indexOfElement(updateOp.id, in: elements),
                        patch: updateOp.patch
                    )
                    elements = result.elements
                    updatedElementIds.append(updateOp.id)
                    for parentID in result.touchedParentIDs where !updatedElementIds.contains(parentID) {
                        updatedElementIds.append(parentID)
                    }

                case .move(let moveOp):
                    let index = try indexOfElement(moveOp.id, in: elements)
                    elements[index] = try moveElement(elements[index], dx: moveOp.dx, dy: moveOp.dy)
                    updatedElementIds.append(moveOp.id)

                case .resize(let resizeOp):
                    let index = try indexOfElement(resizeOp.id, in: elements)
                    elements[index] = try resizeElement(elements[index], op: resizeOp)
                    updatedElementIds.append(resizeOp.id)

                case .delete(let deleteOp):
                    let index = try indexOfElement(deleteOp.id, in: elements)
                    elements[index] = markDeleted(elements[index])
                    deletedElementIds.append(deleteOp.id)

                case .wrap(let wrapOp):
                    let result = try hydrateWrapOp(wrapOp, existingElements: elements)
                    elements.insert(contentsOf: result.elements, at: result.insertionIndex)
                    createdElementIds.append(contentsOf: result.elements.map(\.id))
                    requiresFullReplace = true
            }
        }

        var updatedFile = file
        updatedFile.elements = elements

        return AdjustmentResult(
            file: updatedFile,
            opCounts: opCounts,
            createdElementIds: createdElementIds,
            updatedElementIds: updatedElementIds,
            deletedElementIds: deletedElementIds,
            requiresFullReplace: requiresFullReplace
        )
    }
}

private extension AdjustElementsMiddleware {
    struct AdjustmentError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func indexOfElement(_ id: String, in elements: [ExcalidrawElement]) throws -> Int {
        guard let index = elements.firstIndex(where: { $0.id == id }) else {
            throw AdjustmentError(message: "Element \(id) not found.")
        }
        return index
    }

    func hydrateAddOp(_ op: AddOp, existingElements: [ExcalidrawElement]) throws -> AddOpResult {
        let type = try parseSupportedType(op.element.type)
        let style = hydratedStylePreset(op.element.stylePreset).merged(with: op.element.style)
        let id = op.element.id ?? UUID().uuidString

        switch type {
            case .text:
                return try hydrateTextAdd(op: op, id: id, style: style, existingElements: existingElements)
            case .rectangle, .ellipse, .diamond:
                return hydrateGenericAdd(op: op, type: type, id: id, style: style, existingElements: existingElements)
            case .line:
                return try hydrateLineAdd(op: op, id: id, style: style, existingElements: existingElements)
            case .arrow:
                return try hydrateArrowAdd(op: op, id: id, style: style, existingElements: existingElements)
            default:
                throw AdjustmentError(message: "Unsupported add type: \(type.rawValue)")
        }
    }

    func hydrateWrapOp(_ op: WrapOp, existingElements: [ExcalidrawElement]) throws -> WrapOpResult {
        let targetIDs = uniqueIDs(op.targetIds)
        guard !targetIDs.isEmpty else {
            throw AdjustmentError(message: "wrap requires at least one targetId.")
        }

        let targetIndexes = try targetIDs.map { try indexOfElement($0, in: existingElements) }
        let targets = targetIndexes.map { existingElements[$0] }
        if let deletedID = targets.first(where: { $0.isDeleted })?.id {
            throw AdjustmentError(message: "Cannot wrap deleted element \(deletedID).")
        }

        let shape = try parseWrapType(op.shape)
        let style = hydratedStylePreset(op.stylePreset).merged(with: op.style)
        let bounds = unionBounds(of: targets)
        let padding = max(0, op.padding ?? 24)
        let wrapperX = bounds.minX - padding
        let wrapperY = bounds.minY - padding
        let wrapperWidth = max(1, bounds.maxX - bounds.minX + padding * 2)
        let wrapperHeight = max(1, bounds.maxY - bounds.minY + padding * 2)
        let now = nowMillis()

        let wrapper = ExcalidrawGenericElement(
            type: shape,
            id: UUID().uuidString,
            x: wrapperX,
            y: wrapperY,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 2,
            strokeStyle: .solid,
            roundness: shape == .rectangle ? ExcalidrawRoundness(type: .adaptiveRadius, value: nil) : nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: wrapperWidth,
            height: wrapperHeight,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: now,
            link: nil,
            locked: false,
            customData: nil,
            strokeSharpness: nil
        )

        var createdElements: [ExcalidrawElement] = [.generic(wrapper)]
        if let label = hydratedWrapLabel(
            op.label,
            labelPosition: op.labelPosition,
            wrapperX: wrapperX,
            wrapperY: wrapperY,
            style: style,
            updated: now
        ) {
            createdElements.append(.text(label))
        }

        return WrapOpResult(
            elements: createdElements,
            insertionIndex: targetIndexes.min() ?? existingElements.endIndex
        )
    }

    func hydratedWrapLabel(
        _ rawLabel: String?,
        labelPosition: String?,
        wrapperX: Double,
        wrapperY: Double,
        style: StylePatch,
        updated: Double
    ) -> ExcalidrawTextElement? {
        guard let text = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let fontSize = style.fontSize ?? 18
        let width = defaultTextWidth(text: text, fontSize: fontSize)
        let height = defaultTextHeight(text: text, fontSize: fontSize)
        let labelX = wrapperX + 12
        let labelY: Double
        switch labelPosition {
            case "above":
                labelY = wrapperY - height - 4
            default:
                labelY = wrapperY + 8
        }

        return ExcalidrawTextElement(
            type: .text,
            id: UUID().uuidString,
            x: labelX,
            y: labelY,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 1,
            strokeStyle: .solid,
            roundness: nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: width,
            height: height,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: updated,
            link: nil,
            locked: false,
            customData: nil,
            fontSize: fontSize,
            fontFamily: .int(Int(style.fontFamily ?? 5)),
            text: text,
            textAlign: parseTextAlign(style.textAlign) ?? .left,
            verticalAlign: parseVerticalAlign(style.verticalAlign) ?? .top,
            containerId: nil,
            originalText: text,
            autoResize: true,
            lineHeight: 1.25
        )
    }

    func hydrateTextAdd(
        op: AddOp,
        id: String,
        style: StylePatch,
        existingElements: [ExcalidrawElement]
    ) throws -> AddOpResult {
        let text = (op.element.text ?? op.element.label ?? "Text").trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = style.fontSize ?? 20
        let width = op.element.width ?? defaultTextWidth(text: text, fontSize: fontSize)
        let height = op.element.height ?? defaultTextHeight(text: text, fontSize: fontSize)

        var origin: (x: Double, y: Double)
        var containerId: String? = nil
        var parentBindings: [AddOpResult.ParentBinding] = []

        if let cid = op.element.containerId {
            // Bind text to a container shape — center it inside.
            guard let container = existingElements.first(where: { $0.id == cid }) else {
                throw AdjustmentError(message: "Container \(cid) not found.")
            }
            guard case .generic = container else {
                throw AdjustmentError(message: "Container \(cid) must be rectangle/ellipse/diamond.")
            }
            origin = (
                container.x + (container.width - width) / 2,
                container.y + (container.height - height) / 2
            )
            containerId = cid
            parentBindings.append(.init(parentID: cid, entry: ExcalidrawBoundElement(id: id, type: .text)))
        } else {
            origin = resolveOrigin(for: op.element, place: op.place, existingElements: existingElements)
        }

        let element = ExcalidrawTextElement(
            type: .text,
            id: id,
            x: origin.x,
            y: origin.y,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 1,
            strokeStyle: .solid,
            roundness: nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: width,
            height: height,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: nowMillis(),
            link: nil,
            locked: false,
            customData: nil,
            fontSize: fontSize,
            fontFamily: .int(Int(style.fontFamily ?? 5)),
            text: text,
            textAlign: parseTextAlign(style.textAlign) ?? (containerId != nil ? .center : .left),
            verticalAlign: parseVerticalAlign(style.verticalAlign) ?? (containerId != nil ? .middle : .top),
            containerId: containerId,
            originalText: text,
            autoResize: true,
            lineHeight: 1.25
        )
        return AddOpResult(element: .text(element), parentBindings: parentBindings)
    }

    func hydrateGenericAdd(
        op: AddOp,
        type: ExcalidrawElementType,
        id: String,
        style: StylePatch,
        existingElements: [ExcalidrawElement]
    ) -> AddOpResult {
        let width = op.element.width ?? 160
        let height = op.element.height ?? 100
        let origin = resolveOrigin(for: op.element, place: op.place, existingElements: existingElements)

        let element = ExcalidrawGenericElement(
            type: type,
            id: id,
            x: origin.x,
            y: origin.y,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 2,
            strokeStyle: .solid,
            roundness: type == .rectangle ? ExcalidrawRoundness(type: .adaptiveRadius, value: nil) : nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: width,
            height: height,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: nowMillis(),
            link: nil,
            locked: false,
            customData: nil,
            strokeSharpness: nil
        )
        return AddOpResult(element: .generic(element), parentBindings: [])
    }

    func hydrateLineAdd(
        op: AddOp,
        id: String,
        style: StylePatch,
        existingElements: [ExcalidrawElement]
    ) throws -> AddOpResult {
        let endpoints = resolveLinearEndpoints(op: op, existingElements: existingElements)
        let element = ExcalidrawLinearElement(
            id: id,
            x: endpoints.startX,
            y: endpoints.startY,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 2,
            strokeStyle: .solid,
            roundness: nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: abs(endpoints.dx),
            height: abs(endpoints.dy),
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: nowMillis(),
            link: nil,
            locked: false,
            customData: nil,
            type: .line,
            points: [.zero, CGPoint(x: endpoints.dx, y: endpoints.dy)],
            lastCommittedPoint: nil,
            startBinding: nil,
            endBinding: nil,
            startArrowhead: nil,
            endArrowhead: nil
        )
        return AddOpResult(element: .linear(element), parentBindings: [])
    }

    func hydrateArrowAdd(
        op: AddOp,
        id: String,
        style: StylePatch,
        existingElements: [ExcalidrawElement]
    ) throws -> AddOpResult {
        var startX: Double, startY: Double
        var endX: Double, endY: Double
        var startBinding: PointBinding? = nil
        var endBinding: PointBinding? = nil
        var parentBindings: [AddOpResult.ParentBinding] = []

        if let fromId = op.element.fromId {
            guard let source = existingElements.first(where: { $0.id == fromId }) else {
                throw AdjustmentError(message: "fromId \(fromId) not found.")
            }
            startX = source.x + source.width / 2
            startY = source.y + source.height / 2
            startBinding = .fixed(FixedPointBinding(elementID: fromId, fixedPoint: [0.5, 0.5], mode: .orbit))
            parentBindings.append(.init(parentID: fromId, entry: ExcalidrawBoundElement(id: id, type: .arrow)))
        } else if let x = op.element.x, let y = op.element.y {
            startX = x; startY = y
        } else {
            let origin = resolveOrigin(for: op.element, place: op.place, existingElements: existingElements)
            startX = origin.x; startY = origin.y
        }

        if let toId = op.element.toId {
            guard let target = existingElements.first(where: { $0.id == toId }) else {
                throw AdjustmentError(message: "toId \(toId) not found.")
            }
            endX = target.x + target.width / 2
            endY = target.y + target.height / 2
            endBinding = .fixed(FixedPointBinding(elementID: toId, fixedPoint: [0.5, 0.5], mode: .orbit))
            parentBindings.append(.init(parentID: toId, entry: ExcalidrawBoundElement(id: id, type: .arrow)))
        } else if let ex = op.element.endX, let ey = op.element.endY {
            endX = ex; endY = ey
        } else {
            // Default short rightward arrow.
            endX = startX + (op.element.width ?? 100)
            endY = startY + (op.element.height ?? 0)
        }

        let dx = endX - startX
        let dy = endY - startY
        let arrowhead = parseArrowhead(op.element.arrowhead) ?? .arrow
        let elbowed = op.element.elbowed ?? false

        let element = ExcalidrawArrowElement(
            id: id,
            x: startX,
            y: startY,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 2,
            strokeStyle: .solid,
            roundness: elbowed ? nil : ExcalidrawRoundness(type: .adaptiveRadius, value: nil),
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: abs(dx),
            height: abs(dy),
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: nowMillis(),
            link: nil,
            locked: false,
            customData: nil,
            type: .arrow,
            points: [.zero, CGPoint(x: dx, y: dy)],
            lastCommittedPoint: nil,
            startBinding: startBinding,
            endBinding: endBinding,
            startArrowhead: nil,
            endArrowhead: arrowhead,
            elbowed: elbowed,
            fixedSegments: nil,
            startIsSpecial: nil,
            endIsSpecial: nil
        )
        return AddOpResult(element: .arrow(element), parentBindings: parentBindings)
    }

    func resolveLinearEndpoints(
        op: AddOp,
        existingElements: [ExcalidrawElement]
    ) -> (startX: Double, startY: Double, dx: Double, dy: Double) {
        let startX: Double
        let startY: Double
        if let x = op.element.x, let y = op.element.y {
            startX = x; startY = y
        } else {
            let origin = resolveOrigin(for: op.element, place: op.place, existingElements: existingElements)
            startX = origin.x; startY = origin.y
        }
        let endX = op.element.endX ?? (startX + (op.element.width ?? 100))
        let endY = op.element.endY ?? (startY + (op.element.height ?? 0))
        return (startX, startY, endX - startX, endY - startY)
    }

    func parseArrowhead(_ raw: String?) -> Arrowhead? {
        guard let raw else { return nil }
        return Arrowhead(rawValue: raw)
    }

    /// Append `entry` to `element.boundElements` (skipping duplicates by id+type).
    func appendBoundElement(_ element: ExcalidrawElement, entry: ExcalidrawBoundElement) -> ExcalidrawElement {
        switch element {
            case .generic(var item):
                var bound = item.boundElements ?? []
                if !bound.contains(where: { $0.id == entry.id && $0.type == entry.type }) {
                    bound.append(entry)
                    item.boundElements = bound
                    bump(&item.version, &item.versionNonce, &item.updated)
                }
                return .generic(item)
            case .text(var item):
                var bound = item.boundElements ?? []
                if !bound.contains(where: { $0.id == entry.id && $0.type == entry.type }) {
                    bound.append(entry)
                    item.boundElements = bound
                    bump(&item.version, &item.versionNonce, &item.updated)
                }
                return .text(item)
            default:
                // Linear/arrow can't host bound elements in v1.
                return element
        }
    }

    /// Remove any boundElements entry with the given id from `element`.
    func removeBoundElement(_ element: ExcalidrawElement, id: String) -> ExcalidrawElement {
        switch element {
            case .generic(var item):
                guard var bound = item.boundElements,
                      bound.contains(where: { $0.id == id }) else {
                    return element
                }
                bound.removeAll { $0.id == id }
                item.boundElements = bound
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .text(var item):
                guard var bound = item.boundElements,
                      bound.contains(where: { $0.id == id }) else {
                    return element
                }
                bound.removeAll { $0.id == id }
                item.boundElements = bound
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            default:
                return element
        }
    }

    func patchElement(
        _ elements: [ExcalidrawElement],
        targetIndex: Int,
        patch: ElementPatch
    ) throws -> PatchResult {
        let stylePatch = hydratedStylePreset(patch.stylePreset).merged(with: patch.style)
        var newElements = elements
        var touchedParents: [String] = []
        let element = elements[targetIndex]

        switch element {
            case .text(var item):
                if let text = patch.text ?? patch.label {
                    item.text = text
                    item.originalText = text
                    if patch.bounds?.width == nil {
                        item.width = defaultTextWidth(text: text, fontSize: stylePatch.fontSize ?? item.fontSize)
                    }
                    if patch.bounds?.height == nil {
                        item.height = defaultTextHeight(text: text, fontSize: stylePatch.fontSize ?? item.fontSize)
                    }
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let fontSize = stylePatch.fontSize {
                    item.fontSize = fontSize
                }
                if let fontFamily = stylePatch.fontFamily {
                    item.fontFamily = .int(Int(fontFamily))
                }
                if let textAlign = parseTextAlign(stylePatch.textAlign) {
                    item.textAlign = textAlign
                }
                if let verticalAlign = parseVerticalAlign(stylePatch.verticalAlign) {
                    item.verticalAlign = verticalAlign
                }
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }

                // containerId mutation: bind / unbind text → container shape.
                if let containerPatch = patch.containerId {
                    let oldContainerID = item.containerId
                    let newContainerID = containerPatch.value
                    if oldContainerID != newContainerID {
                        // Detach from old container.
                        if let oldID = oldContainerID,
                           let oldIdx = newElements.firstIndex(where: { $0.id == oldID }) {
                            newElements[oldIdx] = removeBoundElement(newElements[oldIdx], id: item.id)
                            touchedParents.append(oldID)
                        }
                        // Attach to new container (if any) and recenter inside it.
                        if let newID = newContainerID {
                            guard let newIdx = newElements.firstIndex(where: { $0.id == newID }) else {
                                throw AdjustmentError(message: "Container \(newID) not found.")
                            }
                            guard case .generic = newElements[newIdx] else {
                                throw AdjustmentError(message: "Container \(newID) must be rectangle/ellipse/diamond.")
                            }
                            let container = newElements[newIdx]
                            item.x = container.x + (container.width - item.width) / 2
                            item.y = container.y + (container.height - item.height) / 2
                            newElements[newIdx] = appendBoundElement(
                                newElements[newIdx],
                                entry: ExcalidrawBoundElement(id: item.id, type: .text)
                            )
                            touchedParents.append(newID)
                        }
                        item.containerId = newContainerID
                    }
                }

                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .text(item)

            case .generic(var item):
                if patch.text != nil || patch.label != nil {
                    throw AdjustmentError(message: "Text patch is only supported for text elements.")
                }
                if patch.containerId != nil {
                    throw AdjustmentError(message: "containerId only applies to text elements.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .generic(item)

            case .linear(var item):
                if patch.text != nil || patch.label != nil || patch.containerId != nil {
                    throw AdjustmentError(message: "Lines accept only bounds/style patches.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .linear(item)

            case .arrow(var item):
                if patch.text != nil || patch.label != nil || patch.containerId != nil {
                    throw AdjustmentError(message: "Arrows accept only bounds/style patches.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .arrow(item)

            default:
                throw AdjustmentError(message: "Patch only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }

        return PatchResult(elements: newElements, touchedParentIDs: touchedParents)
    }

    func moveElement(_ element: ExcalidrawElement, dx: Double, dy: Double) throws -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                throw AdjustmentError(message: "Move only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }
    }

    func resizeElement(_ element: ExcalidrawElement, op: ResizeOp) throws -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.width = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                item.height = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.width = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                item.height = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                let newW = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                let newH = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                item.points = scaledPoints(item.points, oldW: item.width, oldH: item.height, newW: newW, newH: newH)
                item.width = newW
                item.height = newH
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                let newW = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                let newH = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                item.points = scaledPoints(item.points, oldW: item.width, oldH: item.height, newW: newW, newH: newH)
                item.width = newW
                item.height = newH
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                throw AdjustmentError(message: "Resize only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }
    }

    /// Scale linear points so the bounding box matches `newW × newH`. If a
    /// dimension was 0 (e.g. straight horizontal line has height = 0), leave
    /// that axis alone — there's nothing to scale.
    func scaledPoints(_ points: [Point], oldW: Double, oldH: Double, newW: Double, newH: Double) -> [Point] {
        let sx = oldW > 0 ? newW / oldW : 1
        let sy = oldH > 0 ? newH / oldH : 1
        return points.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
    }

    func markDeleted(_ element: ExcalidrawElement) -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                return element
        }
    }

    func parseSupportedType(_ rawValue: String) throws -> ExcalidrawElementType {
        guard let type = ExcalidrawElementType(rawValue: rawValue) else {
            throw AdjustmentError(message: "Unsupported element type: \(rawValue)")
        }
        switch type {
            case .text, .rectangle, .ellipse, .diamond, .line, .arrow:
                return type
            default:
                throw AdjustmentError(message: "Supported types: text, rectangle, ellipse, diamond, line, arrow.")
        }
    }

    func parseWrapType(_ rawValue: String?) throws -> ExcalidrawElementType {
        guard let rawValue else {
            return .rectangle
        }
        guard let type = ExcalidrawElementType(rawValue: rawValue) else {
            throw AdjustmentError(message: "Unsupported wrap shape: \(rawValue)")
        }
        switch type {
            case .rectangle, .ellipse, .diamond:
                return type
            default:
                throw AdjustmentError(message: "Wrap shape must be rectangle, ellipse, or diamond.")
        }
    }

    func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    func elementBounds(_ element: ExcalidrawElement) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let x2 = element.x + element.width
        let y2 = element.y + element.height
        return (
            min(element.x, x2),
            min(element.y, y2),
            max(element.x, x2),
            max(element.y, y2)
        )
    }

    func unionBounds(of elements: [ExcalidrawElement]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for element in elements {
            let bounds = elementBounds(element)
            minX = min(minX, bounds.minX)
            minY = min(minY, bounds.minY)
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }

        return (minX, minY, maxX, maxY)
    }

    func resolveOrigin(
        for skeleton: ElementSkeleton,
        place: PlaceHint?,
        existingElements: [ExcalidrawElement]
    ) -> (x: Double, y: Double) {
        if let x = skeleton.x, let y = skeleton.y {
            return (x, y)
        }

        if let place,
           let anchor = existingElements.first(where: { $0.id == place.relativeToId }) {
            let gap = place.gap ?? 40
            switch place.position {
                case "right":
                    return (anchor.x + anchor.width + gap, anchor.y)
                case "left":
                    return (anchor.x - (skeleton.width ?? 160) - gap, anchor.y)
                case "above":
                    return (anchor.x, anchor.y - (skeleton.height ?? 100) - gap)
                case "inside":
                    return (anchor.x + gap, anchor.y + gap)
                case "below":
                    fallthrough
                default:
                    return (anchor.x, anchor.y + anchor.height + gap)
            }
        }

        let fallbackX = (existingElements.map { $0.x + $0.width }.max() ?? 80) + 80
        let fallbackY = existingElements.map(\.y).min() ?? 120
        return (skeleton.x ?? fallbackX, skeleton.y ?? fallbackY)
    }

    func hydratedStylePreset(_ preset: String?) -> StylePatch {
        switch preset?.lowercased() {
            case "accent":
                return StylePatch(
                    strokeColor: "#1d4ed8",
                    backgroundColor: "#dbeafe",
                    strokeWidth: 2,
                    roughness: 1,
                    opacity: 100,
                    fontSize: 20,
                    fontFamily: 5,
                    textAlign: "left",
                    verticalAlign: "top"
                )
            case "note":
                return StylePatch(
                    strokeColor: "#92400e",
                    backgroundColor: "#fef3c7",
                    strokeWidth: 2,
                    roughness: 1,
                    opacity: 100,
                    fontSize: 20,
                    fontFamily: 5,
                    textAlign: "left",
                    verticalAlign: "top"
                )
            default:
                return StylePatch(
                    strokeColor: "#1e1e1e",
                    backgroundColor: nil,
                    strokeWidth: 2,
                    roughness: 1,
                    opacity: 100,
                    fontSize: 20,
                    fontFamily: 5,
                    textAlign: "left",
                    verticalAlign: "top"
                )
        }
    }

    /// Per-glyph advance ratios tuned for **Excalifont** (the Excalidraw default
    /// hand-drawn font, fontFamily=5). Excalifont's glyphs run wider than
    /// Helvetica/Virgil at the same point size, so the prior 0.6 ratio was
    /// underestimating Latin width and clipping the trailing characters.
    /// CJK is full-width (≈ 1.0). Anything else (digits, punctuation, latin)
    /// we treat as Latin.
    private static let excalifontLatinAdvance: Double = 0.7
    private static let excalifontCJKAdvance: Double = 1.0
    /// Horizontal padding (≈ glyph cap) so the rightmost glyph doesn't kiss the
    /// edge and trip Excalidraw's wrap heuristic.
    private static let excalifontHorizontalPad: Double = 12

    /// Approximate the rendered width of a single line in Excalifont, treating
    /// CJK ranges as full-width and everything else as Latin. Pre-`measureText`
    /// estimate — accurate enough that the auto-sized text box doesn't clip
    /// at typical sizes; Excalidraw will refine on the JS side once the element
    /// is committed.
    private func excalifontLineWidth(_ line: Substring, fontSize: Double) -> Double {
        var width: Double = 0
        for scalar in line.unicodeScalars {
            let v = scalar.value
            let isCJK =
                (0x4E00...0x9FFF).contains(v) ||      // CJK Unified Ideographs
                (0x3400...0x4DBF).contains(v) ||      // CJK Extension A
                (0x3040...0x30FF).contains(v) ||      // Hiragana / Katakana
                (0xAC00...0xD7AF).contains(v) ||      // Hangul Syllables
                (0xFF00...0xFFEF).contains(v)         // Halfwidth/Fullwidth Forms
            width += fontSize * (isCJK ? Self.excalifontCJKAdvance : Self.excalifontLatinAdvance)
        }
        return width
    }

    func defaultTextWidth(text: String, fontSize: Double) -> Double {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longestLineWidth = lines
            .map { excalifontLineWidth($0, fontSize: fontSize) }
            .max() ?? 0
        // No upper cap — let the box grow with the text. Earlier `min(..., 640)`
        // forced soft-wrap for any longer line, but `defaultTextHeight` only
        // counted explicit \n line breaks, so the wrapped second line clipped.
        return max(60, longestLineWidth + Self.excalifontHorizontalPad)
    }

    func defaultTextHeight(text: String, fontSize: Double) -> Double {
        let lineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        // Excalidraw uses lineHeight ≈ 1.25 × fontSize for hand-drawn fonts.
        // +4pt safety margin: Excalifont has tall ascenders/descenders, and a
        // tight box will clip the bottom of letters like g/p/y.
        return Double(lineCount) * fontSize * 1.25 + 4
    }

    func parseTextAlign(_ rawValue: String?) -> TextAlign? {
        guard let rawValue else { return nil }
        return TextAlign(rawValue: rawValue)
    }

    func parseVerticalAlign(_ rawValue: String?) -> VerticalAlign? {
        guard let rawValue else { return nil }
        return VerticalAlign(rawValue: rawValue)
    }

    func resolvedDimension(current: Double, absolute: Double?, delta: Double?) -> Double {
        if let absolute {
            return max(1, absolute)
        }
        if let delta {
            return max(1, current + delta)
        }
        return current
    }

    func applyBoundsPatch(
        _ x: inout Double,
        _ y: inout Double,
        _ width: inout Double,
        _ height: inout Double,
        _ bounds: BoundsPatch?
    ) {
        guard let bounds else { return }
        if let patchedX = bounds.x {
            x = patchedX
        }
        if let patchedY = bounds.y {
            y = patchedY
        }
        if let patchedWidth = bounds.width {
            width = max(1, patchedWidth)
        }
        if let patchedHeight = bounds.height {
            height = max(1, patchedHeight)
        }
    }

    func applyCommonStylePatch(
        strokeColor: inout String,
        backgroundColor: inout String,
        strokeWidth: inout Double,
        roughness: inout Double,
        opacity: inout Double,
        style: StylePatch?
    ) {
        guard let style else { return }
        if let value = style.strokeColor {
            strokeColor = value
        }
        if let value = style.backgroundColor {
            backgroundColor = value
        }
        if let value = style.strokeWidth {
            strokeWidth = value
        }
        if let value = style.roughness {
            roughness = value
        }
        if let value = style.opacity {
            opacity = value
        }
    }

    func bump(_ version: inout Int, _ versionNonce: inout Int, _ updated: inout Double?) {
        version += 1
        versionNonce = randomNonce()
        updated = nowMillis()
    }

    func randomSeed() -> Int {
        Int.random(in: Int.min / 2 ... Int.max / 2)
    }

    func randomNonce() -> Int {
        Int.random(in: 1 ... Int.max)
    }

    func nowMillis() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}

private extension StylePatch {
    func merged(with override: StylePatch?) -> StylePatch {
        guard let override else { return self }
        return StylePatch(
            strokeColor: override.strokeColor ?? strokeColor,
            backgroundColor: override.backgroundColor ?? backgroundColor,
            strokeWidth: override.strokeWidth ?? strokeWidth,
            roughness: override.roughness ?? roughness,
            opacity: override.opacity ?? opacity,
            fontSize: override.fontSize ?? fontSize,
            fontFamily: override.fontFamily ?? fontFamily,
            textAlign: override.textAlign ?? textAlign,
            verticalAlign: override.verticalAlign ?? verticalAlign
        )
    }
}

private extension ExcalidrawArrowElement {
    init(
        id: String,
        x: Double,
        y: Double,
        strokeColor: String,
        backgroundColor: String,
        fillStyle: ExcalidrawFillStyle,
        strokeWidth: Double,
        strokeStyle: ExcalidrawStrokeStyle,
        roundness: ExcalidrawRoundness?,
        roughness: Double,
        opacity: Double,
        width: Double,
        height: Double,
        angle: Double,
        seed: Int,
        version: Int,
        versionNonce: Int,
        index: String?,
        isDeleted: Bool,
        groupIds: [String],
        frameId: String?,
        boundElements: [ExcalidrawBoundElement]?,
        updated: Double?,
        link: String?,
        locked: Bool?,
        customData: [String: AnyCodable]?,
        type: ExcalidrawElementType,
        points: [Point],
        lastCommittedPoint: Point?,
        startBinding: PointBinding?,
        endBinding: PointBinding?,
        startArrowhead: Arrowhead?,
        endArrowhead: Arrowhead?,
        elbowed: Bool,
        fixedSegments: [FixedSegment]?,
        startIsSpecial: Bool?,
        endIsSpecial: Bool?
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.strokeColor = strokeColor
        self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.roundness = roundness
        self.roughness = roughness
        self.opacity = opacity
        self.width = width
        self.height = height
        self.angle = angle
        self.seed = seed
        self.version = version
        self.versionNonce = versionNonce
        self.index = index
        self.isDeleted = isDeleted
        self.groupIds = groupIds
        self.frameId = frameId
        self.boundElements = boundElements
        self.updated = updated
        self.link = link
        self.locked = locked
        self.customData = customData
        self.type = type
        self.points = points
        self.lastCommittedPoint = lastCommittedPoint
        self.startBinding = startBinding
        self.endBinding = endBinding
        self.startArrowhead = startArrowhead
        self.endArrowhead = endArrowhead
        self.elbowed = elbowed
        self.fixedSegments = fixedSegments
        self.startIsSpecial = startIsSpecial
        self.endIsSpecial = endIsSpecial
    }
}

private extension ExcalidrawTextElement {
    init(
        type: ExcalidrawElementType,
        id: String,
        x: Double,
        y: Double,
        strokeColor: String,
        backgroundColor: String,
        fillStyle: ExcalidrawFillStyle,
        strokeWidth: Double,
        strokeStyle: ExcalidrawStrokeStyle,
        roundness: ExcalidrawRoundness?,
        roughness: Double,
        opacity: Double,
        width: Double,
        height: Double,
        angle: Double,
        seed: Int,
        version: Int,
        versionNonce: Int,
        index: String?,
        isDeleted: Bool,
        groupIds: [String],
        frameId: String?,
        boundElements: [ExcalidrawBoundElement]?,
        updated: Double?,
        link: String?,
        locked: Bool?,
        customData: [String: AnyCodable]?,
        fontSize: Double,
        fontFamily: FontFamily,
        text: String,
        textAlign: TextAlign,
        verticalAlign: VerticalAlign,
        containerId: ExcalidrawGenericElement.ID?,
        originalText: String?,
        autoResize: Bool,
        lineHeight: Double?
    ) {
        self.type = type
        self.id = id
        self.x = x
        self.y = y
        self.strokeColor = strokeColor
        self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.roundness = roundness
        self.roughness = roughness
        self.opacity = opacity
        self.width = width
        self.height = height
        self.angle = angle
        self.seed = seed
        self.version = version
        self.versionNonce = versionNonce
        self.index = index
        self.isDeleted = isDeleted
        self.groupIds = groupIds
        self.frameId = frameId
        self.boundElements = boundElements
        self.updated = updated
        self.link = link
        self.locked = locked
        self.customData = customData
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.text = text
        self.textAlign = textAlign
        self.verticalAlign = verticalAlign
        self.containerId = containerId
        self.originalText = originalText
        self.autoResize = autoResize
        self.lineHeight = lineHeight
    }
}
