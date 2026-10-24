//
//  MathInputSheetView+Workspace.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

extension MathInputSheetView {
    @ViewBuilder
    var workspaceContent: some View {
        switch activeWorkspace {
            case .equation:
                equationWorkspace
            case .function:
                templateWorkspace(
                    title: String(localizable: .toolbarLatexMathFunctionsTitle),
                    subtitle: String(localizable: .toolbarLatexMathFunctionsSubtitle),
                    templates: MathTemplate.functionTemplates,
                    showsSearch: false
                )
            case .geometry:
                templateWorkspace(
                    title: String(localizable: .toolbarLatexMathGeometryTitle),
                    subtitle: String(localizable: .toolbarLatexMathGeometrySubtitle),
                    templates: MathTemplate.geometryTemplates,
                    showsSearch: true
                )
        }
    }

    @ViewBuilder
    var equationWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            formulaTabs

            switch formulaTab {
                case .editor:
                    equationEditor
                case .library:
                    templateWorkspace(
                        title: String(localizable: .toolbarLatexMathFormulaLibraryTitle),
                        subtitle: String(localizable: .toolbarLatexMathFormulaLibrarySubtitle),
                        templates: MathTemplate.equationTemplates,
                        showsSearch: true
                    )
            }
        }
    }

    var equationEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(MathSnippetSection.editorSections) { section in
                snippetSection(section)
            }
        }
    }

    func snippetSection(_ section: MathSnippetSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            LazyVGrid(
                columns: [.init(.adaptive(minimum: section.minimumItemWidth), spacing: 7)],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(section.snippets) { snippet in
                    Button {
                        insertSnippet(snippet.latex)
                    } label: {
                        Text(snippet.display)
                            .font(.system(.body, design: .serif).weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(MathTokenButtonStyle())
                }
            }
        }
    }

    var latexEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(latexEditorTitle.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            TextArea(
                text: isLatexAIModePresented ? $latexAIPrompt : $inputText,
                placeholder: Text(latexEditorPlaceholder)
            )
            .textFont(latexEditorTextFont)
            .textInsets(latexEditorInsets)
            .frame(minHeight: 118, alignment: .topLeading)
            .background {
                latexEditorBackground
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if isLatexAIModePresented {
                    latexAICreditsBadge
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                latexAIControls
                    .padding(8)
            }
        }
    }

    var latexAICreditsBadge: some View {
        HStack(spacing: 5) {
            Image(systemSymbol: hasInsufficientLatexAICredits ? .exclamationmarkTriangleFill : .sparkles)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hasInsufficientLatexAICredits ? .orange : .secondary)

            Text(latexAICreditsText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(hasInsufficientLatexAICredits ? .orange : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            Capsule()
                .fill(.clear)
                .background {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10))
                }
        }
    }

    var latexEditorPlaceholder: String {
        isLatexAIModePresented
            ? String(localizable: .toolbarLatexMathAIPromptPlaceholder)
            : String(localizable: .toolbarLatexMathLatexPlaceholder)
    }

    var latexEditorTitle: String {
        isLatexAIModePresented
            ? String(localizable: .toolbarLatexMathAIPromptTitle)
            : String(localizable: .toolbarLatexMathLatexTitle)
    }

    private var latexEditorInsets: EdgeInsets {
        EdgeInsets(
            top: 12,
            leading: 12,
            bottom: 12,
            trailing: 12
        )
    }

    private var latexEditorTextFont: TextAreaFont {
        isLatexAIModePresented ? .body : .system(design: .monospaced)
    }

    @ViewBuilder
    private var latexEditorBackground: some View {
        if isLatexAIModePresented {
            MathAIDynamicEditorBackground(cornerRadius: 12)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(canvasColorScheme == .dark ? 0.12 : 0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22))
                }
        }
    }

    @ViewBuilder
    var latexAIControls: some View {
        HStack(spacing: 8) {
            if isLatexAIModePresented {
                Button {
                    cancelLatexAIMode()
                } label: {
                    Image(systemSymbol: .xmark)
                }
                .buttonStyle(MathInlineCircleButtonStyle())
                .help(String(localizable: .toolbarLatexMathCancelAIModeHelp))

                Button {
                    if hasInsufficientLatexAICredits {
                        presentLatexAIInsufficientCreditsPaywall()
                    } else {
                        generateLatexWithAI()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingLatex && !hasInsufficientLatexAICredits {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemSymbol: .sparkles)
                        }
                        Text(latexAIActionTitle)
                    }
                }
                .buttonStyle(MathInlineGenerateButtonStyle())
                .disabled(!canUseLatexAIAction)
                .help(
                    hasInsufficientLatexAICredits
                        ? String(localizable: .toolbarLatexMathUpgradeToContinueHelp)
                        : String(localizable: .toolbarLatexMathGenerateLatexHelp)
                )
            } else {
                Button {
                    enterLatexAIMode()
                } label: {
                    Image(systemSymbol: .sparkles)
                }
                .buttonStyle(MathInlineCircleButtonStyle())
                .disabled(!canUseLatexAI)
                .help(
                    canUseLatexAI
                        ? String(localizable: .toolbarLatexMathGenerateWithAIHelp)
                        : String(localizable: .toolbarLatexMathEnableAIInSettingsHelp)
                )
            }
        }
    }

    var canUseLatexAI: Bool {
        AIChatAvailability.isAvailable && aiChatPreferences.isAIEnabled
    }

    var canGenerateLatexWithAI: Bool {
        canUseLatexAI
            && !isGeneratingLatex
            && !latexAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUseLatexAIAction: Bool {
        if hasInsufficientLatexAICredits {
            return canUseLatexAI
        }
        return canGenerateLatexWithAI
    }

    var hasInsufficientLatexAICredits: Bool {
        guard !inferenceBilling.usesBYOK else { return false }
        guard let balance = llmState.creditsInfo?.balance else {
            return false
        }
        return balance <= 0
    }

    var latexAICreditsText: String {
        if inferenceBilling.usesBYOK {
            return String(localizable: .aiBYOKModelBillingNote)
        }
        guard let balance = llmState.creditsInfo?.balance else {
            return String(localizable: .toolbarLatexMathCreditsUnavailable)
        }
        return String(localizable: .toolbarLatexMathCreditsCount(formatLatexAICredits(balance)))
    }

    func formatLatexAICredits(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    var latexAIActionTitle: String {
        if hasInsufficientLatexAICredits {
            return String(localizable: .generalButtonUpgrade)
        }
        return isGeneratingLatex
            ? String(localizable: .toolbarLatexMathGeneratingButton)
            : String(localizable: .toolbarLatexMathGenerateButton)
    }

    func templateWorkspace(
        title: String,
        subtitle: String,
        templates: [MathTemplate],
        showsSearch: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemSymbol: .magnifyingglass)
                        .foregroundStyle(.secondary)
                    TextField(String(localizable: .toolbarLatexMathSearchTemplatesPlaceholder), text: $templateSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(canvasColorScheme == .dark ? 0.12 : 0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.18))
                        }
                }
            }

            LazyVGrid(
                columns: [.init(.adaptive(minimum: 220), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(filteredTemplates(templates)) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(template.category)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(template.latex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .buttonStyle(MathTemplateCardButtonStyle())
                }
            }
        }
    }

    var colorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localizable: .toolbarLatexMathColorSectionTitle).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            ColorButtonGroup(
                colors: ColorPalette.strokeQuickPicks,
                selectedColor: selectedSVGColorForPicker
            ) { color in
                selectedSVGColor = color
                usesThemeDefaultSVGColor = Self.isThemeDefaultSVGColorSelection(color)
                generatePreview(input: inputText)
            }
        }
    }
}
