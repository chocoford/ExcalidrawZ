//
//  AISettingsView+MCP.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import SwiftUI
import SFSafeSymbols

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MCPConnectionGuideTab: Hashable, Identifiable {
    case claude
    case codex
    case vscode

    var id: Self { self }
}

extension AISettingsView {
    @ViewBuilder
    var mcpSettingsSection: some View {
        Section {
            mcpRows
        } header: {
            mcpHeader
                .textCase(nil)
        }
    }

    @ViewBuilder
    var mcpHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizable: .settingsAIMCPTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(localizable: .settingsAIMCPSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if canRunMCPServer {
                mcpConnectionGuideButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpRows: some View {
        if canRunMCPServer {
            Toggle(isOn: mcpServerEnabledBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizable: .settingsAIMCPServerToggleTitle)

                    Text(localizable: .settingsAIMCPServerToggleHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            mcpServiceModeRow

            if usesCompactSettingsLayout {
                compactMCPStatusRow
            } else {
                regularMCPStatusRow
            }
        } else {
            mcpMacOnlyRow
        }
    }

    @ViewBuilder
    var mcpMacOnlyRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemSymbol: .infoCircle)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(localizable: .settingsAIMCPMacOnlyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    var mcpServiceModeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                mcpServiceModeLabel

                Spacer(minLength: 16)

                mcpServiceModePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpServiceModeLabel
                mcpServiceModePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpServiceModeLabel: some View {
        HStack(spacing: 4) {
            Text(localizable: .settingsAIMCPServiceModeTitle)

            Button {
                presentMCPServiceModeHelp()
            } label: {
                Image(systemSymbol: .questionmarkCircle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localizable: .settingsAIMCPServiceModeHelp))
        }
    }

    @ViewBuilder
    var mcpServiceModePicker: some View {
        Picker(
            String(localizable: .settingsAIMCPServiceModeTitle),
            selection: mcpServiceModeBinding
        ) {
            ForEach(ExcalidrawMCPServiceMode.allCases) { mode in
                Text(mcpServiceModeTitle(for: mode))
                    .tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .mcpServiceModePickerShape()
        .fixedSize(horizontal: true, vertical: true)
        .id(mcpServiceModePickerID)
    }

    @ViewBuilder
    var regularMCPStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localizable: .settingsAIMCPStatusLabel)

            Spacer(minLength: 16)

            Text(mcpStatusText)
                .foregroundStyle(mcpStatusColor)
        }
    }

    @ViewBuilder
    var compactMCPStatusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizable: .settingsAIMCPStatusLabel)

            Text(mcpStatusText)
                .foregroundStyle(mcpStatusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpConnectionGuideButton: some View {
        Button {
            isPresentingMCPConnectionGuide = true
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(.localizable(.settingsAIMCPHowToConnectButton), systemSymbol: .link)

                Image(systemSymbol: .link)
            }
            .font(.caption.weight(.semibold))
        }
        .controlSize(.small)
        .help(String(localizable: .settingsAIMCPHowToConnectButton))
    }

    @ViewBuilder
    var mcpConnectionGuideSheet: some View {
        VStack(spacing: 0) {
            mcpConnectionGuideNavigationHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mcpConnectionGuideTabPicker

                    switch selectedMCPConnectionGuideTab {
                        case .claude:
                            mcpClaudeConnectionGuideContent
                                .mcpFeatureRowScrollTransition()

                        case .codex:
                            mcpCodexConnectionGuideContent
                                .mcpFeatureRowScrollTransition()

                        case .vscode:
                            mcpVSCodeConnectionGuideContent
                                .mcpFeatureRowScrollTransition()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabledIfAvailable()
        }
        .mcpConnectionGuideSheetFrame()
    }

    @ViewBuilder
    var mcpServiceModeHelpSheet: some View {
        MCPServiceModeHelpSheet {
            isPresentingMCPServiceModeHelp = false
        }
        .mcpConnectionGuideSheetFrame()
    }

    @ViewBuilder
    var mcpConnectionGuideNavigationHeader: some View {
        ZStack {
            Text(localizable: .settingsAIMCPConnectionGuideTitle)
                .font(.headline)
                .lineLimit(1)

            HStack {
                mcpConnectionGuideCloseButton

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    var mcpConnectionGuideCloseButton: some View {
        mcpSheetCloseButton {
            isPresentingMCPConnectionGuide = false
        }
    }

    @ViewBuilder
    func mcpSheetCloseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemSymbol: .xmark)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.clear, in: Circle())
                    } else {
                        Circle()
                            .fill(.regularMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .contentShape(Circle())
        .help(String(localizable: .generalButtonClose))
    }

    @ViewBuilder
    var mcpConnectionGuideTabPicker: some View {
        HStack(spacing: 2) {
            mcpConnectionGuideTabButton(
                .claude,
                title: String(localizable: .settingsAIMCPConnectionGuideClaudeTabTitle)
            )
            mcpConnectionGuideTabButton(
                .codex,
                title: String(localizable: .settingsAIMCPConnectionGuideCodexTabTitle)
            )
            mcpConnectionGuideTabButton(
                .vscode,
                title: String(localizable: .settingsAIMCPConnectionGuideVSCodeTabTitle)
            )
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    func mcpConnectionGuideTabButton(
        _ tab: MCPConnectionGuideTab,
        title: String
    ) -> some View {
        let isSelected = selectedMCPConnectionGuideTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedMCPConnectionGuideTab = tab
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minWidth: 86, minHeight: 28)
                .padding(.horizontal, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var mcpClaudeConnectionGuideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizable: .settingsAIMCPClaudeDesktopGuideMessage)
                    .foregroundStyle(.secondary)

                Text(localizable: .settingsAIMCPClaudeDesktopGuideSteps)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpGuideSectionHeader(
                    title: String(localizable: .settingsAIMCPClaudeDesktopConfigLabel),
                    copyText: mcpClaudeDesktopClientConfig
                )

                mcpCodeBlock(mcpClaudeDesktopClientConfig)
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpGuideSectionHeader(
                    title: String(localizable: .settingsAIMCPClaudeDesktopConfigPathLabel),
                    copyText: mcpClaudeDesktopConfigPath
                )

                mcpCodeBlock(mcpClaudeDesktopConfigPath)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpCodexConnectionGuideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizable: .settingsAIMCPCodexGuideMessage)
                    .foregroundStyle(.secondary)

                Text(localizable: .settingsAIMCPCodexGuideSteps)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpGuideSectionHeader(
                    title: String(localizable: .settingsAIMCPCodexServerNameLabel),
                    copyText: mcpCodexServerName
                )

                mcpCodeBlock(mcpCodexServerName)
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpGuideSectionHeader(
                    title: String(localizable: .settingsAIMCPCodexServerURLLabel),
                    copyText: mcpEndpoint
                )

                mcpCodeBlock(mcpEndpoint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var mcpVSCodeConnectionGuideContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizable: .settingsAIMCPVSCodeGuideMessage)
                    .foregroundStyle(.secondary)

                Text(localizable: .settingsAIMCPVSCodeGuideSteps)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                mcpGuideSectionHeader(
                    title: String(localizable: .settingsAIMCPVSCodeConfigLabel),
                    copyText: mcpVSCodeClientConfig
                )

                mcpCodeBlock(mcpVSCodeClientConfig)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func mcpCodeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
    }

    @ViewBuilder
    func mcpGuideSectionHeader(title: String, copyText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.headline)

            Spacer(minLength: 12)

            CopyFeedbackButton(
                text: copyText,
                iconFrame: CGSize(width: 16, height: 16),
                iconFont: .callout
            )
            .buttonStyle(.plain)
        }
    }

    var mcpEndpoint: String {
        "http://127.0.0.1:\(mcpServerController.port)/mcp"
    }

    var mcpCodexServerName: String {
        "ExcalidrawZ"
    }

    var mcpClaudeDesktopConfigPath: String {
        "~/Library/Application Support/Claude/claude_desktop_config.json"
    }

    var mcpClaudeDesktopClientConfig: String {
        """
        {
          "mcpServers": {
            "excalidrawz": {
              "command": "npx",
              "args": ["-y", "mcp-remote", "\(mcpEndpoint)"]
            }
          }
        }
        """
    }

    var mcpVSCodeClientConfig: String {
        """
        {
          "servers": {
            "excalidrawz": {
              "type": "http",
              "url": "\(mcpEndpoint)"
            }
          }
        }
        """
    }

    var mcpStatusText: String {
        switch mcpServerController.state {
            case .off:
                String(localizable: .settingsAIMCPStatusOff)
            case .starting:
                String(localizable: .settingsAIMCPStatusStarting)
            case .running:
                String(localizable: .settingsAIMCPStatusRunning)
            case .stopping:
                String(localizable: .settingsAIMCPStatusStopping)
            case .failed:
                String(localizable: .settingsAIMCPStatusFailed)
        }
    }

    var mcpStatusColor: Color {
        switch mcpServerController.state {
            case .off:
                .secondary
            case .starting, .stopping:
                .orange
            case .running:
                .green
            case .failed:
                .red
        }
    }

    var mcpServerEnabledBinding: Binding<Bool> {
        Binding(
            get: { mcpServerController.isEnabled },
            set: { mcpServerController.setEnabled($0) }
        )
    }

    var displayedMCPServiceMode: ExcalidrawMCPServiceMode {
        if mcpServerController.serviceMode == .optimized,
           !store.canUseOptimizedMCPServices {
            return .basic
        }
        return mcpServerController.serviceMode
    }

    var mcpServiceModeBinding: Binding<ExcalidrawMCPServiceMode> {
        Binding(
            get: { displayedMCPServiceMode },
            set: { mode in
                selectMCPServiceMode(mode)
            }
        )
    }

    func selectMCPServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        guard mode != displayedMCPServiceMode else { return }

        if mode == .optimized,
           !store.canUseOptimizedMCPServices {
            mcpServerController.setServiceMode(.basic)
            mcpServiceModePickerID = UUID()
            presentPaywall(reason: .optimizedMCPServices)
            return
        }

        mcpServerController.setServiceMode(mode)
    }

    func mcpServiceModeTitle(for mode: ExcalidrawMCPServiceMode) -> String {
        switch mode {
            case .basic:
                String(localizable: .settingsAIMCPServiceModeBasicTitle)
            case .optimized:
                String(localizable: .settingsAIMCPServiceModeOptimizedTitle)
        }
    }

    func presentMCPServiceModeHelp() {
        isPresentingMCPServiceModeHelp = true
    }

}

private struct MCPServiceModeHelpSheet: View {
    let onClose: () -> Void

    @State private var selectedMode: ExcalidrawMCPServiceMode = .basic

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)

            ScrollView {
                MCPServiceModeFeaturesView(mode: selectedMode)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabledIfAvailable()
        }
        .onAppear {
            selectedMode = .basic
        }
    }

    @ViewBuilder
    private var header: some View {
        ZStack {
            tabPicker

            HStack {
                closeButton

                Spacer(minLength: 0)

                Text(localizable: .settingsAIMCPServiceModeTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemSymbol: .xmark)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.clear, in: Circle())
                    } else {
                        Circle()
                            .fill(.regularMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .controlSize(.regular)
        .contentShape(Circle())
        .help(String(localizable: .generalButtonClose))
    }

    @ViewBuilder
    private var tabPicker: some View {
        MCPServiceModeSegmentedPicker(selection: $selectedMode)
    }
}

struct MCPServiceModeFeaturesPopoverContent: View {
    private let initialMode: ExcalidrawMCPServiceMode

    @State private var selectedMode: ExcalidrawMCPServiceMode

    init(initialMode: ExcalidrawMCPServiceMode = .basic) {
        self.initialMode = initialMode
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 14) {
            MCPServiceModeSegmentedPicker(selection: $selectedMode)
                .zIndex(2)

            ScrollView {
                MCPServiceModeFeaturesView(mode: selectedMode)
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabledIfAvailable()
            .zIndex(0)
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 410, maxWidth: 440)
        .frame(minHeight: 260, idealHeight: 420, maxHeight: 500)
        .onAppear {
            selectedMode = initialMode
        }
    }
}

private struct MCPServiceModeSegmentedPicker: View {
    @Binding var selection: ExcalidrawMCPServiceMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExcalidrawMCPServiceMode.allCases) { mode in
                tabButton(mode)
            }
        }
        .padding(3)
        .background {
            MCPGlassCapsuleBackground(interactive: true)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func tabButton(_ mode: ExcalidrawMCPServiceMode) -> some View {
        let isSelected = selection == mode
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selection = mode
            }
        } label: {
            Text(Self.title(for: mode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minWidth: 92, minHeight: 28)
                .padding(.horizontal, 8)
                .background {
                    if isSelected {
                        MCPSelectedCapsuleBackground()
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    static func title(for mode: ExcalidrawMCPServiceMode) -> String {
        switch mode {
            case .basic:
                String(localizable: .settingsAIMCPServiceModeBasicTitle)
            case .optimized:
                String(localizable: .settingsAIMCPServiceModeOptimizedTitle)
        }
    }
}

private struct MCPServiceModeFeaturesView: View {
    let mode: ExcalidrawMCPServiceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.features(for: mode)) { feature in
                featureRow(feature)
            }
        }
    }

    @ViewBuilder
    private func featureRow(_ feature: MCPServiceModeFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: feature.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background {
                    MCPGlassCircleBackground()
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(feature.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            MCPGlassRoundedBackground(cornerRadius: 18)
        }
        .mcpFeatureRowScrollTransition()
    }

    private static func features(for mode: ExcalidrawMCPServiceMode) -> [MCPServiceModeFeature] {
        switch mode {
            case .basic:
                [
                    MCPServiceModeFeature(
                        id: "basic-focus",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureBasicFocusTitle),
                        body: String(localizable: .settingsAIMCPServiceModeBasicHelp),
                        symbol: .serverRack
                    ),
                    MCPServiceModeFeature(
                        id: "basic-scene",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureBasicSceneTitle),
                        body: String(localizable: .settingsAIMCPServiceModeComparisonBasicDrawingFlow),
                        symbol: .squareOnCircle
                    ),
                    MCPServiceModeFeature(
                        id: "basic-drawing",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureBasicDrawingTitle),
                        body: String(localizable: .settingsAIMCPServiceModeComparisonBasicCanvasTools),
                        symbol: .pencilAndOutline
                    ),
                    MCPServiceModeFeature(
                        id: "basic-revision",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureBasicRevisionTitle),
                        body: String(localizable: .settingsAIMCPServiceModeComparisonBasicHistory),
                        symbol: .arrowTriangle2Circlepath
                    ),
                    MCPServiceModeFeature(
                        id: "basic-compatibility",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureBasicCompatibilityTitle),
                        body: String(localizable: .settingsAIMCPServiceModeComparisonBasicBestFor),
                        symbol: .link
                    )
                ]

            case .optimized:
                [
                    MCPServiceModeFeature(
                        id: "optimized-focus",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedFocusTitle),
                        body: String(localizable: .settingsAIMCPServiceModeOptimizedHelp),
                        symbol: .sparkles
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-incremental",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedIncrementalTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedIncrementalBody),
                        symbol: .pencilAndOutline
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-cross-file",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedCrossFileTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedCrossFileBody),
                        symbol: .folder
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-visual-check",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedVisualCheckTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedVisualCheckBody),
                        symbol: .photo
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-tools",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedToolsTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedToolsBody),
                        symbol: .sparkles
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-library",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedLibraryTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedLibraryBody),
                        symbol: .book
                    ),
                    MCPServiceModeFeature(
                        id: "optimized-export",
                        title: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedExportTitle),
                        body: String(localizable: .settingsAIMCPServiceModeFeatureOptimizedExportBody),
                        symbol: .squareAndArrowUp
                    )
                ]
        }
    }
}

private struct MCPServiceModeFeature: Identifiable {
    let id: String
    let title: String
    let body: String
    let symbol: SFSymbol
}

private struct MCPGlassRoundedBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.clear)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                } else {
                    shape
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                shape
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private struct MCPGlassCapsuleBackground: View {
    let interactive: Bool

    var body: some View {
        Capsule()
            .fill(.clear)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    if interactive {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    } else {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
                    }
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private struct MCPSelectedCapsuleBackground: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.clear.interactive(), in: Capsule())
                }
            }
    }
}

private struct MCPGlassCircleBackground: View {
    var body: some View {
        Circle()
            .fill(.clear)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Circle())
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private extension View {
    @ViewBuilder
    func mcpFeatureRowScrollTransition() -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.scrollTransition(.interactive, axis: .vertical) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.32)
                    .scaleEffect(phase.isIdentity ? 1 : 0.98)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func mcpConnectionGuideSheetFrame() -> some View {
#if os(macOS)
        self.frame(minWidth: 520, idealWidth: 620, minHeight: 320, idealHeight: 420)
#else
        self
#endif
    }

    @ViewBuilder
    func mcpServiceModePickerShape() -> some View {
        if #available(macOS 14.0, *) {
            self
                .buttonBorderShape(.capsule)
                .containerShape(.capsule)
        } else {
            self
        }
    }
}
