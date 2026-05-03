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

    var description: String {
        "Apply a batch of safe Excalidraw edits using a small DSL. Prefer text, rectangle, and ellipse with text, x/y, width/height, relative placement, and stylePreset."
    }

    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "version": ParameterProperty(
                    type: "string",
                    description: "Schema version (default: 1)."
                ),
                "dryRun": ParameterProperty(
                    type: "boolean",
                    description: "If true, validate and hydrate only without applying changes."
                ),
                "ops": ParameterProperty(
                    type: "array",
                    description: "Operations to apply (see schema.json)."
                )
            ],
            required: ["ops"]
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
            opCounts: result.opCounts,
            createdElementIds: result.createdElementIds,
            updatedElementIds: result.updatedElementIds,
            deletedElementIds: result.deletedElementIds
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return String(data: encoded, encoding: .utf8) ?? ""
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
            case let value as Bool:
                return .bool(value)
            case let value as NSNumber:
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
    let createdElementIds: [String]
    let updatedElementIds: [String]
    let deletedElementIds: [String]
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

    var kind: String {
        switch self {
            case .add: return "add"
            case .update: return "update"
            case .move: return "move"
            case .resize: return "resize"
            case .delete: return "delete"
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

private struct ElementSkeleton: Decodable {
    let id: String?
    let type: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let text: String?
    let label: String?
    let fromId: String?
    let toId: String?
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

        let opCounts = payload.ops.reduce(into: [String: Int]()) { partial, op in
            partial[op.kind, default: 0] += 1
        }

        for op in payload.ops {
            switch op {
                case .add(let addOp):
                    let element = try hydrateAddOp(addOp, existingElements: elements)
                    elements.append(element)
                    createdElementIds.append(element.id)

                case .update(let updateOp):
                    let index = try indexOfElement(updateOp.id, in: elements)
                    elements[index] = try patchElement(elements[index], patch: updateOp.patch)
                    updatedElementIds.append(updateOp.id)

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
            }
        }

        var updatedFile = file
        updatedFile.elements = elements

        return AdjustmentResult(
            file: updatedFile,
            opCounts: opCounts,
            createdElementIds: createdElementIds,
            updatedElementIds: updatedElementIds,
            deletedElementIds: deletedElementIds
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

    func hydrateAddOp(_ op: AddOp, existingElements: [ExcalidrawElement]) throws -> ExcalidrawElement {
        let type = try parseSupportedType(op.element.type)
        let style = hydratedStylePreset(op.element.stylePreset).merged(with: op.element.style)
        let origin = resolveOrigin(for: op.element, place: op.place, existingElements: existingElements)
        let id = op.element.id ?? UUID().uuidString

        switch type {
            case .text:
                let text = (op.element.text ?? op.element.label ?? "Text").trimmingCharacters(in: .whitespacesAndNewlines)
                let fontSize = style.fontSize ?? 20
                let width = op.element.width ?? defaultTextWidth(text: text, fontSize: fontSize)
                let height = op.element.height ?? defaultTextHeight(text: text, fontSize: fontSize)
                return .text(
                    ExcalidrawTextElement(
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
                        fontFamily: .int(Int(style.fontFamily ?? 1)),
                        text: text,
                        textAlign: parseTextAlign(style.textAlign) ?? .left,
                        verticalAlign: parseVerticalAlign(style.verticalAlign) ?? .top,
                        containerId: nil,
                        originalText: text,
                        autoResize: true,
                        lineHeight: 1.25
                    )
                )

            case .rectangle, .ellipse:
                let width = op.element.width ?? 160
                let height = op.element.height ?? 100
                return .generic(
                    ExcalidrawGenericElement(
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
                )

            default:
                throw AdjustmentError(message: "Unsupported add type: \(type.rawValue)")
        }
    }

    func patchElement(_ element: ExcalidrawElement, patch: ElementPatch) throws -> ExcalidrawElement {
        let stylePatch = hydratedStylePreset(patch.stylePreset).merged(with: patch.style)
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
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)

            case .generic(var item):
                if patch.text != nil || patch.label != nil {
                    throw AdjustmentError(message: "Text patch is only supported for text elements in v1.")
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
                return .generic(item)

            default:
                throw AdjustmentError(message: "Only text, rectangle, and ellipse are supported in v1.")
        }
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
            default:
                throw AdjustmentError(message: "Only text, rectangle, and ellipse are supported in v1.")
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
            default:
                throw AdjustmentError(message: "Only text, rectangle, and ellipse are supported in v1.")
        }
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
            default:
                return element
        }
    }

    func parseSupportedType(_ rawValue: String) throws -> ExcalidrawElementType {
        guard let type = ExcalidrawElementType(rawValue: rawValue) else {
            throw AdjustmentError(message: "Unsupported element type: \(rawValue)")
        }
        switch type {
            case .text, .rectangle, .ellipse:
                return type
            default:
                throw AdjustmentError(message: "Only text, rectangle, and ellipse are supported in v1.")
        }
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
                    fontFamily: 1,
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
                    fontFamily: 1,
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
                    fontFamily: 1,
                    textAlign: "left",
                    verticalAlign: "top"
                )
        }
    }

    func defaultTextWidth(text: String, fontSize: Double) -> Double {
        let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        let longestLine = Double(text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 1)
        return max(60, min(640, longestLine * fontSize * 0.6 + 24 + Double(lines - 1) * 8))
    }

    func defaultTextHeight(text: String, fontSize: Double) -> Double {
        let lineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        return max(fontSize * 1.25, Double(lineCount) * fontSize * 1.25 + 8)
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
