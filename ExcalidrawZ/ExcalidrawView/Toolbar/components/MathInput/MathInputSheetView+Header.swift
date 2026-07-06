//
//  MathInputSheetView+Header.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI
import SFSafeSymbols

extension MathInputSheetView {
#if os(iOS)
    @ToolbarContentBuilder
    var compactToolbar: some ToolbarContent {
        if usesCompactLayout {
            ToolbarItem(placement: .topBarLeading) {
                mathToolbarCloseButton
            }

            ToolbarItem(placement: .principal) {
                compactWorkspaceSegmentedPicker
            }

            ToolbarItem(placement: .topBarTrailing) {
                mathToolbarCommitButton
            }
        }
    }
#endif

    @ViewBuilder
    var header: some View {
        regularHeader
    }

    var regularHeader: some View {
        ZStack {
            HStack {
                Spacer()

#if os(macOS)
                mathHeaderInspectorToggleButton
#endif
            }

            workspaceSegmentedPicker
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    var mathHeaderCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemSymbol: .xmark)
                .font(.system(size: 16, weight: .semibold))
        }
        .modernButtonStyle(style: .glass, size: .extraLarge, shape: .circle)
        .foregroundStyle(.secondary)
        .help(String(localizable: .generalButtonCancel))
    }

    var mathToolbarCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemSymbol: .xmark)
        }
        .help(String(localizable: .generalButtonCancel))
    }

    var mathHeaderCommitButton: some View {
        Button {
            commitRenderedSVG()
        } label: {
            commitButtonLabel
        }
        .lineLimit(1)
        .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .capsule)
        .keyboardShortcut(.defaultAction)
        .disabled(svgContent == nil)
    }

    var mathToolbarCommitButton: some View {
        Button {
            commitRenderedSVG()
        } label: {
            commitButtonLabel
        }
        .keyboardShortcut(.defaultAction)
        .disabled(svgContent == nil)
    }

#if os(macOS)
    var mathHeaderInspectorToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isInspectorPresented.toggle()
            }
        } label: {
            Image(systemSymbol: .sidebarRight)
                .font(.system(size: 16, weight: .semibold))
        }
        .modernButtonStyle(style: .glass, size: .extraLarge, shape: .circle)
        .foregroundStyle(isInspectorPresented ? Color.accentColor : Color.secondary)
        .help(String(localizable: .toolbarLatexMathTemplatesHelp))
    }
#endif

    var workspaceSegmentedPicker: some View {
        HStack(spacing: 3) {
            ForEach(MathInputWorkspace.visibleCases) { workspace in
                workspaceSegmentButton(workspace)
            }
        }
        .padding(4)
        .background {
            workspaceSegmentedPickerBackground
        }
        .fixedSize(horizontal: true, vertical: true)
        .watch(value: activeWorkspace) { newValue in
            handleWorkspaceSelectionChanged(newValue)
        }
    }

    var compactWorkspaceSegmentedPicker: some View {
        Picker(String(localizable: .toolbarLatexMathFormulaPanelPickerTitle), selection: $activeWorkspace) {
            ForEach(MathInputWorkspace.visibleCases) { workspace in
                Text(workspace.pickerTitle)
                    .tag(workspace)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .mathNativeCapsuleSegmentedPicker()
        .watch(value: activeWorkspace) { newValue in
            handleWorkspaceSelectionChanged(newValue)
        }
    }

    func handleWorkspaceSelectionChanged(_ newValue: MathInputWorkspace) {
        if isLatexAIModePresented {
            cancelLatexAIMode()
        }
        if newValue != .equation {
            templateSearchText = ""
        }
        generatePreview(input: newValue == .function ? functionLatexSource : inputText)
    }

    func workspaceSegmentButton(_ workspace: MathInputWorkspace) -> some View {
        let isSelected = activeWorkspace == workspace
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activeWorkspace = workspace
            }
        } label: {
            HStack(spacing: 6) {
                Text(workspace.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(workspace.shortTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 86, height: 30)
        }
        .modernButtonStyle(
            style: isSelected ? .glassProminent : .glass,
            size: .small,
            shape: .capsule
        )
    }

    @ViewBuilder
    var workspaceSegmentedPickerBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10))
                }
        }
    }

    var formulaTabs: some View {
        Picker(String(localizable: .toolbarLatexMathFormulaPanelPickerTitle), selection: $formulaTab) {
            ForEach(MathFormulaTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .mathNativeCapsuleSegmentedPicker()
        .frame(maxWidth: .infinity)
        .watch(value: formulaTab) { _ in
            templateSearchText = ""
        }
    }
}
