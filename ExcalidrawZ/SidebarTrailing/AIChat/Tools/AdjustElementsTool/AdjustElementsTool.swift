//
//  AdjustElementsTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import CoreGraphics
import LLMCore

struct AdjustElementsTool: Tool {
    struct AdjustElementsContext: ToolContext {
        var currentFileData: Data?
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    }

    var name: String { "adjust_elements" }

    var displayName: String { String(localizable: .aiChatToolAdjustElementName) }

    var description: String {
        return Self.descriptionText
    }

    /// Schema lives in a JSON file shipped with the bundle. The shape uses
    /// `oneOf` over op variants and other JSON Schema features that don't map
    /// cleanly onto the flat `ToolParameters` builder, so we keep it as JSON
    /// and let `.bundleResource` load it at resolve time.
    private static let descriptionText: String = {
        guard let url = Bundle.main.url(
            forResource: "AdjustElementsToolDescription",
            withExtension: "md"
        ),
        let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Apply a batch of safe Excalidraw edits."
        }
        return text
    }()

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
        } catch let error as ToolInput.ValidationError {
            throw ToolError.invalidInput(error.message)
        } catch {
            throw ToolError.invalidInput(
                "Invalid adjust_elements input. Expected a JSON object with top-level `ops` as an array. " +
                "`approvalReason`, when needed, must be a top-level sibling of `ops`."
            )
        }

        guard let context else {
            throw ToolError.executionFailed("Missing AdjustElementsContext")
        }
        let adjustContext = try context.resolve(AdjustElementsContext.self)
        guard let currentFileData = try await CurrentExcalidrawDataResolver.resolveLiveSnapshot(
            canvasTarget: adjustContext.canvasTarget,
            baseContent: adjustContext.currentFileData
        ) else {
            throw ToolError.executionFailed("Missing current file data")
        }

        let currentFile: ExcalidrawFile
        do {
            currentFile = try ExcalidrawFile(data: currentFileData)
        } catch {
            throw ToolError.executionFailed("Invalid Excalidraw file data.")
        }

        let middleware = AdjustElementsMiddleware(file: currentFile)
        let result: AdjustmentResult
        do {
            result = try middleware.apply(payload)
        } catch {
            throw ToolError.executionFailed(Self.describeExecutionError(error))
        }

        let canvasResults: CanvasApplyResult
        do {
            canvasResults = if payload.dryRun ?? false {
                CanvasApplyResult()
            } else {
                try await apply(result, canvasTarget: adjustContext.canvasTarget)
            }
        } catch {
            throw ToolError.executionFailed(Self.describeExecutionError(error))
        }

        let output = ToolOutput(
            ok: true,
            version: payload.version ?? "1",
            dryRun: payload.dryRun ?? false,
            opCount: payload.ops.count,
            opCounts: result.opCounts,
            mermaidResults: canvasResults.mermaidResults.isEmpty ? nil : canvasResults.mermaidResults,
            skeletonResults: canvasResults.skeletonResults.isEmpty ? nil : canvasResults.skeletonResults,
            connectResults: canvasResults.connectResults.isEmpty ? nil : canvasResults.connectResults
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return .text(String(data: encoded, encoding: .utf8) ?? "")
    }

    private static func describeExecutionError(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private extension AdjustElementsTool {
    @MainActor
    func apply(
        _ result: AdjustmentResult,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> CanvasApplyResult {
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

        let cameraDirector = ExcalidrawCoordinatorRegistry.shared.cameraDirector(for: canvasTarget)
        let changedElementIDs = result.createdElementIds + result.updatedElementIds
        if !changedElementIDs.isEmpty || !result.deletedElementIds.isEmpty {
            try await cameraDirector.submitMutationBatch(
                elements: result.file.elements,
                changedElementIDs: changedElementIDs
            )
        }

        var mermaidResults: [ExcalidrawCore.MermaidInsertResult] = []
        var skeletonResults: [ExcalidrawCore.SkeletonInsertResult] = []
        var connectResults: [ExcalidrawCore.ConnectElementsResult] = []
        for action in result.canvasActions {
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
                    skeletonResults.append(insertResult)
                    try await cameraDirector.submitInsertedContentBounds(makeRect(from: insertResult.bounds))
                case .connect(let op):
                    let connectResult = try await coordinator.connectElements(
                        from: op.from,
                        to: op.to,
                        arrow: op.arrow,
                        captureUpdate: op.captureUpdate
                    )
                    connectResults.append(connectResult)
            }
        }
        return CanvasApplyResult(
            mermaidResults: mermaidResults,
            skeletonResults: skeletonResults,
            connectResults: connectResults
        )
    }

    func makeRect(from bounds: ExcalidrawCore.MermaidBounds) -> CGRect {
        CGRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
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

struct ToolOutput: Encodable {
    let ok: Bool
    let version: String
    let dryRun: Bool
    let opCount: Int
    let opCounts: [String: Int]
    let mermaidResults: [ExcalidrawCore.MermaidInsertResult]?
    let skeletonResults: [ExcalidrawCore.SkeletonInsertResult]?
    let connectResults: [ExcalidrawCore.ConnectElementsResult]?
}

private struct CanvasApplyResult {
    var mermaidResults: [ExcalidrawCore.MermaidInsertResult] = []
    var skeletonResults: [ExcalidrawCore.SkeletonInsertResult] = []
    var connectResults: [ExcalidrawCore.ConnectElementsResult] = []
}

struct ToolInput: Decodable {
    struct ValidationError: Error {
        let message: String
    }

    let version: String?
    let dryRun: Bool?
    let ops: [Operation]

    private enum CodingKeys: String, CodingKey {
        case version
        case dryRun
        case ops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)

        do {
            ops = try container.decode([Operation].self, forKey: .ops)
        } catch DecodingError.typeMismatch {
            throw ValidationError(
                message: "Invalid adjust_elements input: `ops` must be a JSON array, not a string or object. " +
                "Put `approvalReason` at the top level next to `ops`."
            )
        } catch DecodingError.valueNotFound {
            throw ValidationError(message: "Invalid adjust_elements input: `ops` is required and must be a JSON array.")
        } catch DecodingError.keyNotFound {
            throw ValidationError(message: "Invalid adjust_elements input: missing required top-level `ops` array.")
        } catch {
            throw ValidationError(
                message: "Invalid adjust_elements input: one or more entries in `ops` do not match the supported operation schema."
            )
        }
    }
}

enum Operation: Decodable {
    case add(AddOp)
    case addLabeledShape(AddLabeledShapeOp)
    case update(UpdateOp)
    case move(MoveOp)
    case resize(ResizeOp)
    case delete(DeleteOp)
    case wrap(WrapOp)
    case mermaid(MermaidOp)
    case connect(ConnectOp)

    var kind: String {
        switch self {
            case .add: return "add"
            case .addLabeledShape: return "addLabeledShape"
            case .update: return "update"
            case .move: return "move"
            case .resize: return "resize"
            case .delete: return "delete"
            case .wrap: return "wrap"
            case .mermaid: return "mermaid"
            case .connect: return "connect"
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
            case "addLabeledShape":
                self = .addLabeledShape(try AddLabeledShapeOp(from: decoder))
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
            case "mermaid":
                self = .mermaid(try MermaidOp(from: decoder))
            case "connect":
                self = .connect(try ConnectOp(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .op,
                    in: container,
                    debugDescription: "Unsupported op: \(op)"
                )
        }
    }
}

struct AddOp: Decodable {
    let op: String
    let elements: ExcalidrawCore.JSONValue
    let layout: String?
    let layoutOptions: [String: ExcalidrawCore.JSONValue]?
    let place: PlaceHint?
    let regenerateIds: Bool?
    let position: ExcalidrawCore.MermaidPosition?
    let focus: ExcalidrawCore.MermaidFocus?
    let files: [String: ExcalidrawCore.JSONValue]?
    let captureUpdate: ExcalidrawCore.CaptureUpdate?
    let sanitize: Bool?
}

struct AddLabeledShapeOp: Decodable {
    let op: String
    let shape: String?
    let text: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let stylePreset: String?
    let style: StylePatch?
}

struct UpdateOp: Decodable {
    let op: String
    let id: String
    let patch: ElementPatch
}

struct MoveOp: Decodable {
    let op: String
    let id: String
    let dx: Double
    let dy: Double
}

struct ResizeOp: Decodable {
    let op: String
    let id: String
    let width: Double?
    let height: Double?
    let dw: Double?
    let dh: Double?
    let anchor: String?
}

struct DeleteOp: Decodable {
    let op: String
    let id: String
}

struct WrapOp: Decodable {
    let op: String
    let targetIds: [String]
    let shape: String?
    let padding: Double?
    let stylePreset: String?
    let style: StylePatch?
    let label: String?
    let labelPosition: String?
}

struct MermaidOp: Decodable {
    let op: String
    let definition: String
    let position: ExcalidrawCore.MermaidPosition?
    let focus: ExcalidrawCore.MermaidFocus?
    let regenerateIds: Bool?
    let mermaidConfig: ExcalidrawCore.JSONValue?
    let captureUpdate: ExcalidrawCore.CaptureUpdate?
}

struct ConnectOp: Decodable {
    let op: String
    let from: String
    let to: String
    let arrow: ExcalidrawCore.JSONValue?
    let captureUpdate: ExcalidrawCore.CaptureUpdate?
}

struct SkeletonInsertAction {
    let skeletons: ExcalidrawCore.JSONValue
    let layout: String?
    let layoutOptions: [String: ExcalidrawCore.JSONValue]?
    let regenerateIds: Bool?
    let position: ExcalidrawCore.MermaidPosition?
    let focus: ExcalidrawCore.MermaidFocus?
    let files: [String: ExcalidrawCore.JSONValue]?
    let captureUpdate: ExcalidrawCore.CaptureUpdate?
    let sanitize: Bool?
}

struct ElementSkeleton: Decodable {
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

struct PlaceHint: Decodable {
    let relativeToId: String
    let position: String
    let gap: Double?
}

struct ElementPatch: Decodable {
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

struct BoundsPatch: Decodable {
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
}

struct StylePatch: Decodable {
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

struct AdjustmentResult {
    let file: ExcalidrawFile
    let opCounts: [String: Int]
    let createdElementIds: [String]
    let updatedElementIds: [String]
    let deletedElementIds: [String]
    let requiresFullReplace: Bool
    let canvasActions: [CanvasAction]
}

enum CanvasAction {
    case insertMermaid(MermaidOp)
    case insertSkeleton(SkeletonInsertAction)
    case connect(ConnectOp)
}

/// Result of hydrating an `add` op: the new element plus any boundElements
/// entries that need to be appended to existing parent elements (text→container,
/// arrow→source/target shapes).
struct AddOpResult {
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
struct PatchResult {
    let elements: [ExcalidrawElement]
    let touchedParentIDs: [String]
}

/// Result of hydrating a `wrap` op. We add wrapper elements incrementally
/// instead of full-replacing the scene, so consecutive tool calls don't erase
/// elements that the WebView has applied before Swift file state catches up.
struct WrapOpResult {
    let elements: [ExcalidrawElement]
}

struct AddLabeledShapeOpResult {
    let elements: [ExcalidrawElement]
}

struct AdjustElementsMiddleware {
    private let file: ExcalidrawFile

    init(file: ExcalidrawFile) {
        self.file = file
    }

    func apply(_ payload: ToolInput) throws -> AdjustmentResult {
        var elements = file.elements
        var createdElementIds: [String] = []
        var updatedElementIds: [String] = []
        var deletedElementIds: [String] = []
        var canvasActions: [CanvasAction] = []
        let requiresFullReplace = false

        let opCounts = payload.ops.reduce(into: [String: Int]()) { partial, op in
            partial[op.kind, default: 0] += 1
        }

        for op in payload.ops {
            switch op {
                case .add(let addOp):
                    try applyAddOp(
                        addOp,
                        elements: &elements,
                        canvasActions: &canvasActions
                    )

                case .addLabeledShape(let addLabeledShapeOp):
                    try applyAddLabeledShapeOp(
                        addLabeledShapeOp,
                        elements: &elements,
                        createdElementIds: &createdElementIds
                    )

                case .update(let updateOp):
                    try applyUpdateOp(
                        updateOp,
                        elements: &elements,
                        updatedElementIds: &updatedElementIds
                    )

                case .move(let moveOp):
                    try applyMoveOp(
                        moveOp,
                        elements: &elements,
                        updatedElementIds: &updatedElementIds
                    )

                case .resize(let resizeOp):
                    try applyResizeOp(
                        resizeOp,
                        elements: &elements,
                        updatedElementIds: &updatedElementIds
                    )

                case .delete(let deleteOp):
                    try applyDeleteOp(
                        deleteOp,
                        elements: &elements,
                        deletedElementIds: &deletedElementIds
                    )

                case .wrap(let wrapOp):
                    try applyWrapOp(
                        wrapOp,
                        elements: &elements,
                        createdElementIds: &createdElementIds
                    )

                case .mermaid(let mermaidOp):
                    try applyMermaidOp(mermaidOp, canvasActions: &canvasActions)

                case .connect(let connectOp):
                    try applyConnectOp(
                        connectOp,
                        elements: elements,
                        canvasActions: &canvasActions
                    )

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
            requiresFullReplace: requiresFullReplace,
            canvasActions: canvasActions
        )
    }
}

extension AdjustElementsMiddleware {
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
                return element
        }
    }

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

    func resolveInsertionOrigin(
        height: Double,
        existingElements: [ExcalidrawElement]
    ) -> (x: Double, y: Double) {
        let visibleElements = existingElements.filter { !$0.isDeleted }
        guard !visibleElements.isEmpty else {
            return (80, 120)
        }

        let bounds = unionBounds(of: visibleElements)
        return (
            x: bounds.maxX + 80,
            y: bounds.minY + max(0, (bounds.maxY - bounds.minY - height) / 2)
        )
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

extension StylePatch {
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

extension ExcalidrawArrowElement {
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

extension ExcalidrawTextElement {
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
