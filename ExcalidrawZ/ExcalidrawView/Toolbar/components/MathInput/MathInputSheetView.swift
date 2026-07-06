//
//  MathInputSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import Logging
import LLMKit

import ChocofordUI

struct MathInputSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject private var canvasPreferencesState: CanvasPreferencesState
    @EnvironmentObject var llmState: LLMStateObject
    @ObservedObject var aiChatPreferences = AIChatPreferences.shared

    let logger = Logger(label: "MathInputSheetView")

    var mode: MathInputSheetMode
    var onAIInsufficientCredits: ((_ snapshot: MathInputSheetSnapshot) -> Void)?
    var onCommit: (_ renderedSVG: MathRenderedSVG) -> Void

    @State var inputText: String
    @State var selectedSVGColor: String
    @State var usesThemeDefaultSVGColor: Bool
    @State var activeWorkspace: MathInputWorkspace = .equation
    @State var formulaTab: MathFormulaTab = .editor
    @State var functionPanelTab: MathFunctionPanelTab = .input
    @State var templateSearchText: String = ""

    @State var functionExpressions: [MathFunctionExpression]
    @State var functionXMin: String = "-10"
    @State var functionXMax: String = "10"
    @State var functionYMin: String = "-10"
    @State var functionYMax: String = "10"
    @State var functionXLabel: String = "x"
    @State var functionYLabel: String = "y"
    @State var functionShowGrid: Bool = true
    @State var functionBackgroundColor: String? = nil

    @State var svgContent: MathRenderedSVG?
    @State var error: Error?
    @State var previewTask: Task<Void, Never>?
    @State var isLatexAIModePresented = false
    @State var latexAIPrompt: String = ""
    @State var isGeneratingLatex = false
    @State var latexAIGenerationTask: Task<Void, Never>?
#if os(macOS)
    @State var isInspectorPresented: Bool = true
#endif

    init(
        mode: MathInputSheetMode = .insert,
        initialLatex: String = "",
        initialSVGColor: String = "#1e1e1e",
        restoredSnapshot: MathInputSheetSnapshot? = nil,
        onAIInsufficientCredits: ((_ snapshot: MathInputSheetSnapshot) -> Void)? = nil,
        onCommit: @escaping (_ renderedSVG: MathRenderedSVG) -> Void
    ) {
        self.mode = mode
        self.onAIInsufficientCredits = onAIInsufficientCredits
        self.onCommit = onCommit
        let inputText = restoredSnapshot?.inputText ?? initialLatex
        let selectedSVGColor = restoredSnapshot?.selectedSVGColor ?? initialSVGColor
        self._inputText = State(initialValue: inputText)
        self._selectedSVGColor = State(initialValue: selectedSVGColor)
        self._usesThemeDefaultSVGColor = State(
            initialValue: restoredSnapshot?.usesThemeDefaultSVGColor
                ?? Self.isThemeDefaultSVGColor(selectedSVGColor)
        )
        self._activeWorkspace = State(initialValue: restoredSnapshot?.activeWorkspace ?? .equation)
        self._formulaTab = State(initialValue: restoredSnapshot?.formulaTab ?? .editor)
        self._functionPanelTab = State(initialValue: restoredSnapshot?.functionPanelTab ?? .input)
        self._templateSearchText = State(initialValue: restoredSnapshot?.templateSearchText ?? "")
        self._functionExpressions = State(
            initialValue: restoredSnapshot?.functionExpressions ?? [
                MathFunctionExpression(
                    expression: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "y = x" : inputText,
                    colorHex: "#6865db"
                )
            ]
        )
        self._functionXMin = State(initialValue: restoredSnapshot?.functionXMin ?? "-10")
        self._functionXMax = State(initialValue: restoredSnapshot?.functionXMax ?? "10")
        self._functionYMin = State(initialValue: restoredSnapshot?.functionYMin ?? "-10")
        self._functionYMax = State(initialValue: restoredSnapshot?.functionYMax ?? "10")
        self._functionXLabel = State(initialValue: restoredSnapshot?.functionXLabel ?? "x")
        self._functionYLabel = State(initialValue: restoredSnapshot?.functionYLabel ?? "y")
        self._functionShowGrid = State(initialValue: restoredSnapshot?.functionShowGrid ?? true)
        self._functionBackgroundColor = State(initialValue: restoredSnapshot?.functionBackgroundColor)
        self._isLatexAIModePresented = State(initialValue: restoredSnapshot?.isLatexAIModePresented ?? false)
        self._latexAIPrompt = State(initialValue: restoredSnapshot?.latexAIPrompt ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !usesCompactLayout {
                header
            }

            contentLayout

            if !usesCompactLayout {
                Divider()
                footer
            }
        }
#if os(macOS)
        .mathInputInspector(isPresented: $isInspectorPresented) {
            ScrollView {
                rightPanelContent
                    .padding(18)
            }
        }
        .frame(width: 920, height: 680)
#endif
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            compactToolbar
        }
#endif
        .onChange(of: inputText, debounce: 0.2) { newValue in
            guard !isLatexAIModePresented else {
                return
            }
            generatePreview(input: newValue)
        }
        .onChange(of: functionPreviewConfiguration, debounce: 0.2) { _ in
            guard activeWorkspace == .function else {
                return
            }
            generatePreview(input: functionLatexSource)
        }
        .onAppear {
            generatePreview(input: activeWorkspace == .function ? functionLatexSource : inputText)
        }
        .watch(value: canvasColorScheme) { _ in
            guard !isLatexAIModePresented else {
                return
            }
            generatePreview(input: activeWorkspace == .function ? functionLatexSource : inputText)
        }
        .onDisappear {
            previewTask?.cancel()
            latexAIGenerationTask?.cancel()
        }
    }

    var functionPreviewConfiguration: MathFunctionPreviewConfiguration {
        MathFunctionPreviewConfiguration(
            expressions: functionExpressions,
            xMin: functionXMin,
            xMax: functionXMax,
            yMin: functionYMin,
            yMax: functionYMax,
            xLabel: functionXLabel,
            yLabel: functionYLabel,
            showGrid: functionShowGrid,
            backgroundColor: functionBackgroundColor
        )
    }

    var canvasColorScheme: ColorScheme {
        canvasPreferencesState.theme.colorScheme
    }

    var canvasBackgroundColor: String {
        let color = canvasPreferencesState.viewBackgroundColor
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return color.isEmpty ? "#ffffff" : color
    }

    var usesCompactLayout: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    @ViewBuilder
    var contentLayout: some View {
#if os(macOS)
        if activeWorkspace == .function {
            GeometryReader { proxy in
                functionLeftPanelContent(availableSize: proxy.size)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else {
            ScrollView {
                leftPanelContent
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
#else
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewArea
                if activeWorkspace == .function {
                    functionPanel
                } else {
                    drawingSettings
                    latexEditor
                }
                workspaceContent
            }
            .padding(20)
        }
#endif
    }

    var leftPanelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            previewArea
            if activeWorkspace == .function {
                functionPanel
            } else {
                drawingSettings
                latexEditor
            }
        }
    }

    func functionLeftPanelContent(availableSize: CGSize) -> some View {
        let maximumPreviewHeight = min(max(availableSize.width - 40, 220), 320)
        let previewHeight = min(
            max(availableSize.height * 0.46, 220),
            maximumPreviewHeight
        )

        return VStack(alignment: .leading, spacing: 18) {
            previewCard(cornerRadius: 28)
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)

            functionDrawingSettings
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var rightPanelContent: some View {
        if activeWorkspace == .function {
            functionInspectorContent
        } else {
            workspaceContent
        }
    }
}

#Preview {
    MathInputSheetView { _ in

    }
    .environmentObject(CanvasPreferencesState())
}
