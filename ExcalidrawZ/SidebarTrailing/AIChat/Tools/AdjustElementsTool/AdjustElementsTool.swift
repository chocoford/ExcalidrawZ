//
//  AdjustElementsTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore
import SwiftUI

struct AdjustElementsTool: Tool {
    struct AdjustElementsContext: ToolContext {
        var currentFileData: Data?
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
        var currentFileID: UUID? = nil
        var imageAttachments: [AIChatImageAttachmentReference] = []
    }

    var name: String { "adjust_elements" }

    var displayName: String { String(localizable: .aiChatToolAdjustElementName) }

    var description: String {
        return [
            Self.imageSkeletonAttachmentDescription,
            Self.descriptionText
        ].joined(separator: "\n\n")
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

    private static let imageSkeletonAttachmentDescription = """
    Important image insertion rule: represent an image attached in the current chat turn with \
    `source: { "kind": "attachment", "id": "input_image_1" }` in the `add` image skeleton. \
    Attachment ids follow user-message image order (`input_image_1`, `input_image_2`, ...). \
    The tool preprocesses that source into a real Excalidraw `fileId` plus `add.files` entry \
    before inserting. Inline `dataURL`, raw `base64`, and public HTTPS image `url` sources are \
    also accepted when real image bytes are available.
    """

    var inputSchema: ToolInputSchema {
        .bundleResource(name: "AdjustElementsToolSchema")
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        guard let data = input.data(using: .utf8) else {
            throw ToolError.invalidInput("Invalid input format. Expected JSON string.")
        }

        let payload: ToolInput
        do {
            payload = try ToolInput.decodeLeniently(from: data)
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
        guard try await LockedContentAIGuard.canToolAccess(
            canvasTarget: adjustContext.canvasTarget,
            currentFileID: adjustContext.currentFileID
        ) else {
            return LockedContentAIGuard.lockedToolResult
        }
        if adjustContext.canvasTarget.targetsProposalCanvas,
           payload.dryRun != true {
            await AIProposalSandbox.resetCanvasIfAvailable()
        }
        guard let currentFileData = try await CurrentExcalidrawDataResolver.resolveLiveSnapshot(
            canvasTarget: adjustContext.canvasTarget,
            baseContent: adjustContext.currentFileData,
            currentFileID: adjustContext.currentFileID
        ) else {
            throw ToolError.executionFailed("Missing current file data")
        }

        let currentFile: ExcalidrawFile
        do {
            currentFile = try ExcalidrawFile(data: currentFileData)
        } catch {
            throw ToolError.executionFailed("Invalid Excalidraw file data.")
        }

        let middleware = AdjustElementsMiddleware(
            file: currentFile,
            imageAttachments: adjustContext.imageAttachments
        )
        let result: AdjustmentResult
        do {
            result = try await middleware.apply(payload)
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

        let proposal = try await makeProposalArtifactIfNeeded(
            canvasTarget: adjustContext.canvasTarget,
            dryRun: payload.dryRun ?? false
        )
        let outputSurface = ToolOutputSurface(
            canvasTarget: adjustContext.canvasTarget,
            dryRun: payload.dryRun ?? false
        )
        let proposalSourceInput = proposal == nil ? nil : ToolOutputJSONValue.parseObject(from: input)

        let output = ToolOutput(
            ok: true,
            version: payload.version ?? "1",
            dryRun: payload.dryRun ?? false,
            canvasTarget: outputSurface.canvasTarget,
            assistantInstruction: outputSurface.assistantInstruction,
            opCount: payload.ops.count,
            opCounts: result.opCounts,
            mermaidResults: canvasResults.mermaidResults.isEmpty ? nil : canvasResults.mermaidResults,
            latexResults: canvasResults.latexResults.isEmpty ? nil : canvasResults.latexResults,
            skeletonResults: canvasResults.skeletonResults.isEmpty ? nil : canvasResults.skeletonResults,
            connectResults: canvasResults.connectResults.isEmpty ? nil : canvasResults.connectResults,
            proposalSummary: Self.makeProposalSummary(
                proposal: proposal,
                opCount: payload.ops.count,
                opCounts: result.opCounts
            ),
            proposalSourceInput: proposalSourceInput,
            proposalRevisionHint: proposal == nil ? nil : "If the user asks to revise this proposal later, use proposalSourceInput as the base and call adjust_elements with a complete replacement input for the revised proposal on the proposal canvas.",
            proposal: proposal
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        let outputText = String(data: encoded, encoding: .utf8) ?? ""
        return .text(outputText)
    }

    static func describeExecutionError(_ error: Error) -> String {
        if let javaScriptError = describeJavaScriptException(error) {
            return javaScriptError
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    static func makeProposalSummary(
        proposal: AIProposalArtifact?,
        opCount: Int,
        opCounts: [String: Int]
    ) -> String? {
        guard let proposal else { return nil }
        let counts = opCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let countsText = counts.isEmpty ? "none" : counts
        return "Created an AI proposal on the proposal canvas with \(proposal.elementCount) visible element(s) from \(opCount) operation(s) (\(countsText)). The user's file has not changed unless they apply the proposal."
    }

    private static func describeJavaScriptException(_ error: Error) -> String? {
        var visited: Set<ObjectIdentifier> = []
        return describeJavaScriptException(error as NSError, visited: &visited)
    }

    private static func describeJavaScriptException(
        _ error: NSError,
        visited: inout Set<ObjectIdentifier>
    ) -> String? {
        let identifier = ObjectIdentifier(error)
        guard !visited.contains(identifier) else { return nil }
        visited.insert(identifier)

        if isJavaScriptException(error) {
            var parts = ["JavaScript exception"]
            if let message = javaScriptUserInfoString(error, key: "WKJavaScriptExceptionMessage"),
               !message.isEmpty {
                parts.append("message: \(message)")
            } else {
                parts.append("message: \(error.localizedDescription)")
            }
            if let sourceURL = javaScriptUserInfoString(error, key: "WKJavaScriptExceptionSourceURL"),
               !sourceURL.isEmpty {
                parts.append("source: \(sourceURL)")
            }
            if let line = javaScriptUserInfoString(error, key: "WKJavaScriptExceptionLineNumber") {
                parts.append("line: \(line)")
            }
            if let column = javaScriptUserInfoString(error, key: "WKJavaScriptExceptionColumnNumber") {
                parts.append("column: \(column)")
            }
            parts.append("webkit: \(error.domain) code \(error.code)")
            return parts.joined(separator: "; ")
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return describeJavaScriptException(underlying, visited: &visited)
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return describeJavaScriptException(underlying)
        }
        return nil
    }

    private static func isJavaScriptException(_ error: NSError) -> Bool {
        error.domain == "WKErrorDomain" ||
            error.userInfo.keys.contains("WKJavaScriptExceptionMessage") ||
            error.userInfo.keys.contains("WKJavaScriptExceptionLineNumber")
    }

    private static func javaScriptUserInfoString(_ error: NSError, key: String) -> String? {
        guard let value = error.userInfo[key] else { return nil }
        return String(describing: value)
    }

}

private extension AdjustElementsTool {
    @MainActor
    func apply(
        _ result: AdjustmentResult,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> CanvasApplyResult {
        try await ExcalidrawCanvasActionApplier.apply(result, canvasTarget: canvasTarget)
    }

    @MainActor
    func makeProposalArtifactIfNeeded(
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget,
        dryRun: Bool
    ) async throws -> AIProposalArtifact? {
        guard canvasTarget.targetsProposalCanvas, !dryRun else { return nil }
        guard let data = try await CurrentExcalidrawDataResolver.resolveLiveSnapshot(
            canvasTarget: .proposal,
            baseContent: AIProposalSandbox.blankFileData()
        ) else {
            return nil
        }
        let file = try ExcalidrawFile(data: data)
        guard file.elements.contains(where: { !$0.isDeleted }) else {
            return nil
        }
        return AIProposalArtifact(file: file)
    }

}

private struct ToolOutput: Encodable {
    let ok: Bool
    let version: String
    let dryRun: Bool
    let canvasTarget: String
    let assistantInstruction: String
    let opCount: Int
    let opCounts: [String: Int]
    let mermaidResults: [ExcalidrawCore.MermaidInsertResult]?
    let latexResults: [LatexInsertResult]?
    let skeletonResults: [ExcalidrawCore.SkeletonInsertResult]?
    let connectResults: [ExcalidrawCore.ConnectElementsResult]?
    let proposalSummary: String?
    let proposalSourceInput: ToolOutputJSONValue?
    let proposalRevisionHint: String?
    let proposal: AIProposalArtifact?
}

private enum ToolOutputJSONValue: Encodable {
    case object([String: ToolOutputJSONValue])
    case array([ToolOutputJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func parseObject(from raw: String) -> ToolOutputJSONValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let resolvedObject = resolveStringifiedJSONObjectIfNeeded(object),
              let value = ToolOutputJSONValue(resolvedObject),
              case .object = value else {
            return nil
        }
        return value
    }

    private static func resolveStringifiedJSONObjectIfNeeded(_ value: Any) -> Any? {
        guard let string = value as? String else { return value }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object
    }

    init?(_ value: Any) {
        switch value {
        case let dictionary as [String: Any]:
            var object: [String: ToolOutputJSONValue] = [:]
            for (key, value) in dictionary {
                guard let encoded = ToolOutputJSONValue(value) else { return nil }
                object[key] = encoded
            }
            self = .object(object)

        case let array as [Any]:
            var values: [ToolOutputJSONValue] = []
            values.reserveCapacity(array.count)
            for item in array {
                guard let encoded = ToolOutputJSONValue(item) else { return nil }
                values.append(encoded)
            }
            self = .array(values)

        case let string as String:
            self = .string(string)

        case let bool as Bool:
            self = .bool(bool)

        case let number as NSNumber:
            self = .number(number.doubleValue)

        case _ as NSNull:
            self = .null

        default:
            return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for key in object.keys.sorted() {
                try container.encode(object[key], forKey: DynamicCodingKey(key))
            }

        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }

        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)

        case .number(let number):
            var container = encoder.singleValueContainer()
            try container.encode(number)

        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)

        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

private struct ToolOutputSurface {
    let canvasTarget: String
    let assistantInstruction: String

    init(canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget, dryRun: Bool) {
        if dryRun {
            self.canvasTarget = canvasTarget.targetsProposalCanvas ? "proposal" : "user_document"
            self.assistantInstruction = "Dry run only. No canvas changes were applied."
        } else if canvasTarget.targetsProposalCanvas {
            self.canvasTarget = "proposal"
            self.assistantInstruction = "The changes were created on an AI proposal canvas. Tell the user this is a proposal and that they can Apply it if they want it. Describe the file or user canvas as updated after the user applies the proposal."
        } else {
            self.canvasTarget = "user_document"
            self.assistantInstruction = "The changes were applied directly to the user's current Excalidraw file."
        }
    }
}

struct CanvasApplyResult {
    var mermaidResults: [ExcalidrawCore.MermaidInsertResult] = []
    var latexResults: [LatexInsertResult] = []
    var skeletonResults: [ExcalidrawCore.SkeletonInsertResult] = []
    var connectResults: [ExcalidrawCore.ConnectElementsResult] = []
}

struct LatexInsertResult: Codable, Hashable {
    var elementId: String?
    var elementCount: Int
    var durationMs: Double?
    var usedLegacyFallback: Bool?
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

    init(
        version: String? = nil,
        dryRun: Bool? = nil,
        ops: [Operation]
    ) {
        self.version = version
        self.dryRun = dryRun
        self.ops = ops
    }

    static func decodeLeniently(from data: Data) throws -> ToolInput {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ToolInput.self, from: data)
        } catch let error as ValidationError {
            throw error
        } catch {
            if let stringifiedInput = try? decoder.decode(String.self, from: data) {
                return try decodeStringifiedToolInput(stringifiedInput)
            }
            throw error
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)

        do {
            ops = try container.decode([Operation].self, forKey: .ops)
        } catch {
            if let stringifiedOps = try? container.decode(String.self, forKey: .ops) {
                ops = try Self.decodeStringifiedOps(stringifiedOps)
                return
            }

            switch error {
            case DecodingError.typeMismatch(_, _):
                throw ValidationError(
                    message: "Invalid adjust_elements input: `ops` must be a JSON array, not a string or object. " +
                    "Put `approvalReason` at the top level next to `ops`."
                )
            case DecodingError.valueNotFound(_, _):
                throw ValidationError(message: "Invalid adjust_elements input: `ops` is required and must be a JSON array.")
            case DecodingError.keyNotFound(_, _):
                throw ValidationError(message: "Invalid adjust_elements input: missing required top-level `ops` array.")
            default:
                throw ValidationError(
                    message: "Invalid adjust_elements input: one or more entries in `ops` do not match the supported operation schema."
                )
            }
        }
    }

    private static func decodeStringifiedToolInput(_ value: String) throws -> ToolInput {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw ValidationError(
                message: "Invalid adjust_elements input: stringified tool input was empty. Pass a JSON object."
            )
        }

        do {
            return try JSONDecoder().decode(ToolInput.self, from: data)
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError(
                message: "Invalid adjust_elements input: tool input was provided as a JSON string, but the string did not contain a valid input object. Pass a JSON object."
            )
        }
    }

    private static func decodeStringifiedOps(_ value: String) throws -> [Operation] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw ValidationError(
                message: "Invalid adjust_elements input: stringified `ops` was empty. Pass `ops` as a JSON array."
            )
        }

        do {
            return try JSONDecoder().decode([Operation].self, from: data)
        } catch {
            throw ValidationError(
                message: "Invalid adjust_elements input: `ops` was provided as a JSON string, but the string did not contain a valid operation array. Pass `ops` as a JSON array."
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
    case latex(LatexOp)
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
            case .latex: return "latex"
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
            case "latex", "math":
                self = .latex(try LatexOp(from: decoder))
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

struct LatexOp: Decodable {
    let op: String
    let latex: String
    let color: String?
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

extension SkeletonInsertAction {
    var inputElementReferenceIds: [String] {
        skeletons.skeletonInputElementIds()
    }
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
    case insertLatex(LatexOp)
    case insertSkeleton(SkeletonInsertAction)
    case connect(ConnectOp)

    var pendingElementReferenceIds: [String] {
        switch self {
            case .insertSkeleton(let action):
                return action.inputElementReferenceIds
            case .insertMermaid, .insertLatex, .connect:
                return []
        }
    }
}

private extension ExcalidrawCore.JSONValue {
    func skeletonInputElementIds() -> [String] {
        switch self {
            case .array(let values):
                return values.compactMap(\.directSkeletonInputElementId)
            case .object(_):
                return directSkeletonInputElementId.map { [$0] } ?? []
            case .string(_), .number(_), .bool(_), .null:
                return []
        }
    }

    var directSkeletonInputElementId: String? {
        guard case .object(let object) = self,
              case .string? = object["type"],
              case .string(let id)? = object["id"]
        else {
            return nil
        }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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

/// Result of hydrating a `wrap` op. The wrapper itself must sit behind its
/// targets, so callers use the insertion index with a full scene replace.
struct WrapOpResult {
    let elements: [ExcalidrawElement]
    let backgroundInsertIndex: Int
}

struct AddLabeledShapeOpResult {
    let elements: [ExcalidrawElement]
}

struct AdjustElementsMiddleware {
    private let file: ExcalidrawFile
    let imageAttachments: [AIChatImageAttachmentReference]

    init(
        file: ExcalidrawFile,
        imageAttachments: [AIChatImageAttachmentReference] = []
    ) {
        self.file = file
        self.imageAttachments = imageAttachments
    }

    func apply(_ payload: ToolInput) async throws -> AdjustmentResult {
        var elements = file.elements
        var createdElementIds: [String] = []
        var updatedElementIds: [String] = []
        var deletedElementIds: [String] = []
        var canvasActions: [CanvasAction] = []
        var pendingCanvasElementIds = Set<String>()
        var requiresFullReplace = false

        let opCounts = payload.ops.reduce(into: [String: Int]()) { partial, op in
            partial[op.kind, default: 0] += 1
        }

        for (index, op) in payload.ops.enumerated() {
            do {
                switch op {
                    case .add(let addOp):
                        let actionStartIndex = canvasActions.count
                        try await applyAddOp(
                            addOp,
                            elements: &elements,
                            canvasActions: &canvasActions
                        )
                        for action in canvasActions.dropFirst(actionStartIndex) {
                            pendingCanvasElementIds.formUnion(action.pendingElementReferenceIds)
                        }

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
                        requiresFullReplace = true
                        try applyWrapOp(
                            wrapOp,
                            elements: &elements,
                            createdElementIds: &createdElementIds
                        )

                    case .mermaid(let mermaidOp):
                        try applyMermaidOp(mermaidOp, canvasActions: &canvasActions)

                    case .latex(let latexOp):
                        try applyLatexOp(latexOp, canvasActions: &canvasActions)

                    case .connect(let connectOp):
                        try applyConnectOp(
                            connectOp,
                            elements: elements,
                            pendingElementIds: pendingCanvasElementIds,
                            canvasActions: &canvasActions
                        )

                }
            } catch {
                throw OperationExecutionError(index: index, kind: op.kind, underlying: error)
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

    struct OperationExecutionError: LocalizedError {
        let index: Int
        let kind: String
        let underlying: Error

        var errorDescription: String? {
            let detail = (underlying as? LocalizedError)?.errorDescription ?? underlying.localizedDescription
            return "Operation #\(index + 1) (\(kind)) failed: \(detail)"
        }
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
