//
//  InsertMathTool.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/20.
//

import Foundation
import LLMCore

/// Dedicated math insertion tool for AI. This keeps formula/function insertion
/// discoverable without forcing the model through the broader adjust_elements
/// operation schema.
struct InsertMathTool: Tool {
    struct MathContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
        var currentFileID: UUID? = nil
    }

    var name: String { "insert_math" }

    var displayName: String { String(localizable: .aiChatToolMathName) }

    var description: String {
        """
        Insert math content into the current Excalidraw canvas. Use mode=formula \
        for a LaTeX formula rendered through MathJax, or mode=function for a \
        plotted function graph rendered as a math image. Prefer this tool over \
        adjust_elements when the user asks to add an equation, formula, LaTeX \
        expression, graph, or function plot.
        """
    }

    var inputSchema: ToolInputSchema {
        .bundleResource(name: "InsertMathToolSchema")
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let payload = try InsertMathToolInput.decodeLeniently(from: input)
        guard let context else {
            throw ToolError.executionFailed("Missing MathContext")
        }
        let mathContext = try context.resolve(MathContext.self)
        guard try await LockedContentAIGuard.canToolAccess(
            canvasTarget: mathContext.canvasTarget,
            currentFileID: mathContext.currentFileID
        ) else {
            return LockedContentAIGuard.lockedToolResult
        }

        if mathContext.canvasTarget.targetsProposalCanvas {
            await AIProposalSandbox.resetCanvasIfAvailable()
        }

        let renderedSVG = try await render(payload)
        let insertResult = try await insert(
            renderedSVG,
            position: payload.position ?? .auto,
            focus: payload.focus ?? true,
            canvasTarget: mathContext.canvasTarget
        )
        let proposal = try await makeProposalArtifactIfNeeded(canvasTarget: mathContext.canvasTarget)

        let output = InsertMathToolOutput(
            ok: true,
            mode: payload.resolvedMode.rawValue,
            canvasTarget: mathContext.canvasTarget.targetsProposalCanvas ? "proposal" : "user_document",
            assistantInstruction: mathContext.canvasTarget.targetsProposalCanvas
                ? "Math content was rendered on the proposal canvas. Ask the user to apply it if they want it committed to the real file."
                : "Math content was inserted into the user's file.",
            source: renderedSVG.source,
            renderer: renderedSVG.renderer,
            elementId: insertResult.elementId,
            fileId: insertResult.fileId,
            elementCount: insertResult.elementCount ?? (insertResult.elementId == nil ? 0 : 1),
            width: insertResult.width ?? renderedSVG.width,
            height: insertResult.height ?? renderedSVG.height,
            bounds: insertResult.bounds,
            usedLegacyFallback: insertResult.usedLegacyFallback,
            proposal: proposal
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(output)
        return .text(String(data: encoded, encoding: .utf8) ?? "")
    }

    @MainActor
    private func render(_ input: InsertMathToolInput) async throws -> MathRenderedSVG {
        switch input.resolvedMode {
            case .formula:
                let latex = try input.resolvedLatex
                return try await MathRenderService.shared.renderLatex(
                    latex,
                    foregroundColor: input.resolvedFormulaColor
                )
            case .function:
                let request = try input.functionPlotRequest
                return try await MathRenderService.shared.render(.functionPlot(request))
        }
    }

    @MainActor
    private func insert(
        _ renderedSVG: MathRenderedSVG,
        position: ExcalidrawCore.MermaidPosition,
        focus: Bool,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> ExcalidrawCore.MathImageResult {
        guard let coordinator = try await ExcalidrawCoordinatorRegistry.shared.resolvedCoordinator(
            for: canvasTarget
        ) else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

        return try await coordinator.insertMathImage(
            params: renderedSVG.mathImageParams,
            options: .init(
                position: position,
                focus: focus ? .mode(.center) : .enabled(false),
                captureUpdate: .immediately
            )
        )
    }

    @MainActor
    private func makeProposalArtifactIfNeeded(
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> AIProposalArtifact? {
        guard canvasTarget.targetsProposalCanvas else { return nil }
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

private struct InsertMathToolInput: Decodable {
    enum Mode: String, Decodable {
        case formula
        case function
    }

    struct FunctionExpression: Decodable {
        var expression: String
        var color: String?

        init(expression: String, color: String?) {
            self.expression = expression
            self.color = color
        }

        private enum CodingKeys: String, CodingKey {
            case expression
            case color
            case colorHex = "color_hex"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            expression = try container.decode(String.self, forKey: .expression)
            color = try container.decodeIfPresent(String.self, forKey: .color)
                ?? container.decodeIfPresent(String.self, forKey: .colorHex)
        }
    }

    var mode: Mode?
    var latex: String?
    var expression: String?
    var color: String?
    var expressions: [FunctionExpression]?
    var expressionsJSON: String?
    var width: Double?
    var height: Double?
    var xMin: Double?
    var xMax: Double?
    var yMin: Double?
    var yMax: Double?
    var xLabel: String?
    var yLabel: String?
    var showGrid: Bool?
    var backgroundColor: String?
    var focus: Bool?
    var position: ExcalidrawCore.MermaidPosition?

    private enum CodingKeys: String, CodingKey {
        case mode
        case latex
        case expression
        case color
        case expressions
        case expressionsJSON = "expressions_json"
        case width
        case height
        case xMin = "x_min"
        case xMax = "x_max"
        case yMin = "y_min"
        case yMax = "y_max"
        case xLabel = "x_label"
        case yLabel = "y_label"
        case showGrid = "show_grid"
        case backgroundColor = "background_color"
        case focus
        case position
    }

    static func decodeLeniently(from input: String) throws -> Self {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ToolError.invalidInput("Invalid math input. Expected a JSON object.")
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            if let stringified = try? decoder.decode(String.self, from: data),
               let stringifiedData = stringified.data(using: .utf8) {
                return try decoder.decode(Self.self, from: stringifiedData)
            }
            throw ToolError.invalidInput("Invalid math input. Expected mode=formula with latex, or mode=function with expressions.")
        }
    }

    var resolvedMode: Mode {
        if let mode {
            return mode
        }
        return expressions?.isEmpty == false ? .function : .formula
    }

    var resolvedLatex: String {
        get throws {
            guard resolvedMode == .formula else { return "" }
            let value = (latex ?? expression ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                throw ToolError.invalidInput("Formula mode requires `latex`.")
            }
            return value
        }
    }

    var resolvedFormulaColor: String {
        normalizeHexColor(color) ?? Self.defaultFormulaColor
    }

    var functionPlotRequest: MathFunctionPlotRenderRequest {
        get throws {
            let expressions = try resolvedFunctionExpressions
            let xMin = xMin ?? -10
            let xMax = xMax ?? 10
            let yMin = yMin ?? -10
            let yMax = yMax ?? 10
            guard xMin < xMax else {
                throw ToolError.invalidInput("Function mode requires x_min < x_max.")
            }
            guard yMin < yMax else {
                throw ToolError.invalidInput("Function mode requires y_min < y_max.")
            }

            return MathFunctionPlotRenderRequest(
                expressions: expressions,
                width: clampedDimension(width, fallback: 520),
                height: clampedDimension(height, fallback: 520),
                xMin: xMin,
                xMax: xMax,
                yMin: yMin,
                yMax: yMax,
                xLabel: xLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "x",
                yLabel: yLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "y",
                showGrid: showGrid ?? true,
                backgroundColor: normalizedBackgroundColor,
                usesDarkPresentation: false
            )
        }
    }

    private var resolvedFunctionExpressions: [MathFunctionPlotExpression] {
        get throws {
            let inputExpressions: [FunctionExpression]
            if let expressions {
                inputExpressions = expressions
            } else if let decodedExpressions = try decodedExpressionsJSON {
                inputExpressions = decodedExpressions
            } else if let expression {
                inputExpressions = [FunctionExpression(expression: expression, color: nil)]
            } else {
                inputExpressions = []
            }
            let resolved = inputExpressions.enumerated().compactMap { index, item -> MathFunctionPlotExpression? in
                let expression = item.expression.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !expression.isEmpty else { return nil }
                return MathFunctionPlotExpression(
                    expression: expression,
                    colorHex: normalizeHexColor(item.color) ?? Self.defaultFunctionColors[index % Self.defaultFunctionColors.count]
                )
            }
            guard !resolved.isEmpty else {
                throw ToolError.invalidInput("Function mode requires at least one non-empty expression.")
            }
            return resolved
        }
    }

    private var decodedExpressionsJSON: [FunctionExpression]? {
        get throws {
            guard let value = expressionsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            guard let data = value.data(using: .utf8) else {
                throw ToolError.invalidInput("Function mode `expressions_json` must be a valid JSON array string.")
            }
            do {
                return try JSONDecoder().decode([FunctionExpression].self, from: data)
            } catch {
                throw ToolError.invalidInput("Function mode `expressions_json` must be a JSON array of objects with `expression` and optional `color`.")
            }
        }
    }

    private var normalizedBackgroundColor: String? {
        guard let value = backgroundColor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "transparent" else {
            return nil
        }
        return normalizeHexColor(value)
    }

    private static let defaultFormulaColor = "#1e1e1e"

    private static let defaultFunctionColors = [
        "#635bff",
        "#ef4444",
        "#22c55e",
        "#f59e0b",
        "#8b5cf6",
        "#06b6d4"
    ]

    private func clampedDimension(_ value: Double?, fallback: Double) -> Double {
        min(max(value ?? fallback, 180), 1600)
    }

    private func normalizeHexColor(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard [3, 6, 8].contains(hex.count),
              hex.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return "#\(hex)"
    }
}

private struct InsertMathToolOutput: Encodable {
    var ok: Bool
    var mode: String
    var canvasTarget: String
    var assistantInstruction: String
    var source: String
    var renderer: String
    var elementId: String?
    var fileId: String?
    var elementCount: Int
    var width: Double?
    var height: Double?
    var bounds: ExcalidrawCore.MermaidBounds?
    var usedLegacyFallback: Bool?
    var proposal: AIProposalArtifact?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
