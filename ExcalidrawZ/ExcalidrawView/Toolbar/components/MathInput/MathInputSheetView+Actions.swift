//
//  MathInputSheetView+Actions.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI
import LLMCore
import LLMKit

extension MathInputSheetView {
    @MainActor
    func generatePreview(input: String) {
        logger.debug("[MathInputSheetView] generatePreview for \(input)")
        previewTask?.cancel()
        error = nil
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            svgContent = nil
            return
        }

        let request = previewRenderRequest(input: input)
        previewTask = Task {
            do {
                let renderedSVG = try await MathRenderService.shared.render(request)
                guard !Task.isCancelled else { return }
                svgContent = renderedSVG
            }
            catch {
                guard !Task.isCancelled else { return }
                logger.error("[MathInputSheetView] error: \(error)")
                self.error = error
                svgContent = nil
            }
        }
    }

    func previewRenderRequest(input: String) -> MathRenderRequest {
        switch activeWorkspace {
            case .equation, .geometry:
                return .latex(
                    MathLatexRenderRequest(
                        latex: input,
                        foregroundColor: resolvedSVGColorForRendering
                    )
                )
            case .function:
                return .functionPlot(
                    MathFunctionPlotRenderRequest(
                        expressions: functionExpressions.map {
                            MathFunctionPlotExpression(
                                expression: $0.expression,
                                colorHex: $0.colorHex
                            )
                        },
                        width: 520,
                        height: 520,
                        xMin: tryFunctionPlotNumber(functionXMin, fallback: -10),
                        xMax: tryFunctionPlotNumber(functionXMax, fallback: 10),
                        yMin: tryFunctionPlotNumber(functionYMin, fallback: -10),
                        yMax: tryFunctionPlotNumber(functionYMax, fallback: 10),
                        xLabel: functionXLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "x",
                        yLabel: functionYLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "y",
                        showGrid: functionShowGrid,
                        backgroundColor: functionBackgroundColor,
                        usesDarkPresentation: false
                    )
                )
        }
    }

    func tryFunctionPlotNumber(_ value: String, fallback: Double) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    }

    func errorDescription(for error: Error) -> String {
        if let error = error as? LocalizedError {
            return error.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    func insertSnippet(_ latex: String) {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInput.isEmpty {
            inputText = latex
        } else {
            let separator = inputText.hasSuffix(" ") || inputText.hasSuffix("\n") ? "" : " "
            inputText += separator + latex
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            activeWorkspace = .equation
            formulaTab = .editor
        }
        generatePreview(input: inputText)
    }

    func applyTemplate(_ template: MathTemplate) {
        if activeWorkspace == .function {
            let color = functionColorPalette[functionExpressions.count % functionColorPalette.count]
            withAnimation(.easeInOut(duration: 0.18)) {
                functionExpressions.append(
                    MathFunctionExpression(
                        expression: template.latex,
                        colorHex: color
                    )
                )
            }
            functionPanelTab = .input
            generatePreview(input: functionLatexSource)
            return
        }

        inputText = template.latex
        withAnimation(.easeInOut(duration: 0.18)) {
            if activeWorkspace == .equation {
                formulaTab = .editor
            }
        }
        generatePreview(input: inputText)
    }

    func filteredTemplates(_ templates: [MathTemplate]) -> [MathTemplate] {
        let query = templateSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return templates
        }

        return templates.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.category.localizedCaseInsensitiveContains(query)
                || $0.latex.localizedCaseInsensitiveContains(query)
        }
    }

    var functionColorPalette: [String] {
        ["#6865db", "#e03131", "#2f9e44", "#f08c00", "#1971c2", "#9c36b5"]
    }

    var functionLatexSource: String {
        let expressions = functionExpressions
            .map { $0.expression.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !expressions.isEmpty else {
            return ""
        }
        guard expressions.count > 1 else {
            return expressions[0]
        }

        return "\\begin{aligned} " + expressions.joined(separator: " \\\\ ") + " \\end{aligned}"
    }

    func addFunctionExpression() {
        let defaultExpressions = ["y = x", "y = x^2", "y = \\sin(x)", "y = \\cos(x)"]
        let index = functionExpressions.count
        let expression = defaultExpressions[index % defaultExpressions.count]
        let color = functionColorPalette[index % functionColorPalette.count]

        withAnimation(.easeInOut(duration: 0.18)) {
            functionExpressions.append(
                MathFunctionExpression(
                    expression: expression,
                    colorHex: color
                )
            )
        }
        generatePreview(input: functionLatexSource)
    }

    func updateFunctionExpression(id: UUID, expression: String) {
        guard let index = functionExpressions.firstIndex(where: { $0.id == id }) else {
            return
        }

        functionExpressions[index].expression = expression
        generatePreview(input: functionLatexSource)
    }

    func removeFunctionExpression(id: UUID) {
        guard functionExpressions.count > 1 else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            functionExpressions.removeAll { $0.id == id }
        }
        generatePreview(input: functionLatexSource)
    }

    func enterLatexAIMode() {
        guard canUseLatexAI else {
            return
        }

        previewTask?.cancel()
        error = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            isLatexAIModePresented = true
        }
    }

    func cancelLatexAIMode() {
        latexAIGenerationTask?.cancel()
        latexAIGenerationTask = nil
        isGeneratingLatex = false

        withAnimation(.easeInOut(duration: 0.18)) {
            isLatexAIModePresented = false
        }
    }

    func generateLatexWithAI() {
        guard canGenerateLatexWithAI else {
            return
        }
        if !inferenceBilling.usesBYOK,
           let balance = llmState.creditsInfo?.balance, balance <= 0 {
            presentLatexAIInsufficientCreditsPaywall()
            return
        }

        let prompt = latexAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        latexAIGenerationTask?.cancel()
        isGeneratingLatex = true
        error = nil
        let billingRevision = inferenceBilling.modelCatalogRevision

        latexAIGenerationTask = Task { @MainActor in
            defer {
                isGeneratingLatex = false
                latexAIGenerationTask = nil
            }

            do {
                let response: APIResponse<ChatMessageContent> = try await inferenceBilling.withSelectedBilling(expectedRevision: billingRevision) {
                    let model = try inferenceBilling.modelForAuxiliaryRequest(fallback: .qwen3_6Plus)
                    return try await inferenceBilling.selectedInferenceClient().chat(
                        model: model,
                        system: latexAIGenerationSystemPrompt,
                        text: prompt,
                        metadata: MathLatexAIGenerationMetadata()
                    )
                }

                guard !Task.isCancelled else { return }

                if let apiError = response.error {
                    if apiError.code == 402 {
                        presentLatexAIInsufficientCreditsPaywall()
                        return
                    }
                    throw LLMError.server(statusCode: apiError.code, message: apiError.message)
                }

                guard let content = response.data?.content,
                      let generatedLatex = Self.generatedLatex(from: content) else {
                    throw MathLatexAIGenerationError.emptyResponse
                }

                inputText = generatedLatex
                withAnimation(.easeInOut(duration: 0.18)) {
                    isLatexAIModePresented = false
                }
                generatePreview(input: generatedLatex)
            } catch {
                guard !Task.isCancelled else { return }
                if let llmError = error as? LLMError,
                   case .insufficientCredits = llmError {
                    presentLatexAIInsufficientCreditsPaywall()
                    return
                }
                logger.error("[MathInputSheetView] latex AI generation error: \(error)")
                self.error = AIInferenceErrorMessage.localizedError(for: error) ?? error
            }
        }
    }

    func presentLatexAIInsufficientCreditsPaywall() {
        let snapshot = makeMathInputSnapshot()
        if let onAIInsufficientCredits {
            onAIInsufficientCredits(snapshot)
        } else {
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
        }
    }

    func makeMathInputSnapshot() -> MathInputSheetSnapshot {
        MathInputSheetSnapshot(
            inputText: inputText,
            selectedSVGColor: selectedSVGColor,
            usesThemeDefaultSVGColor: usesThemeDefaultSVGColor,
            activeWorkspace: activeWorkspace,
            formulaTab: formulaTab,
            functionPanelTab: functionPanelTab,
            templateSearchText: templateSearchText,
            functionExpressions: functionExpressions,
            functionXMin: functionXMin,
            functionXMax: functionXMax,
            functionYMin: functionYMin,
            functionYMax: functionYMax,
            functionXLabel: functionXLabel,
            functionYLabel: functionYLabel,
            functionShowGrid: functionShowGrid,
            functionBackgroundColor: functionBackgroundColor,
            isLatexAIModePresented: isLatexAIModePresented,
            latexAIPrompt: latexAIPrompt,
            clipboardText: mathInputClipboardText
        )
    }

    var mathInputClipboardText: String {
        if isLatexAIModePresented {
            return latexAIPrompt
        }
        if activeWorkspace == .function {
            return functionLatexSource
        }
        return inputText
    }

    var latexAIGenerationSystemPrompt: String {
        """
        You convert user requests into LaTeX math expressions for MathJax SVG rendering.
        Return only raw LaTeX.
        Do not use Markdown fences, explanations, or surrounding delimiters like $...$, $$...$$, \\(...\\), or \\[...\\].
        Prefer concise, valid MathJax-compatible LaTeX.
        """
    }

    static func generatedLatex(from response: String) -> String? {
        var output = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.hasPrefix("```") {
            var lines = output
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            if !lines.isEmpty {
                lines.removeFirst()
            }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            output = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let delimiters: [(String, String)] = [
            ("\\[", "\\]"),
            ("\\(", "\\)"),
            ("$$", "$$"),
            ("$", "$")
        ]

        for delimiter in delimiters {
            if output.hasPrefix(delimiter.0), output.hasSuffix(delimiter.1) {
                output = String(output.dropFirst(delimiter.0.count).dropLast(delimiter.1.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return output.isEmpty ? nil : output
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct MathLatexAIGenerationMetadata: Codable, Equatable, Sendable {
    var source: String = "math_input"
}

private enum MathLatexAIGenerationError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
            case .emptyResponse:
                String(localizable: .toolbarLatexMathAIEmptyResponseError)
        }
    }
}
