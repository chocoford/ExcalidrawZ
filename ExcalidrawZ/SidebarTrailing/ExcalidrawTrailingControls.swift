//
//  ExcalidrawTrailingControls.swift
//  ExcalidrawZ
//
//  Created by OpenAI on 2025/2/14.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols
#if canImport(UIKit)
import UIKit
#endif

struct ExcalidrawTrailingControls: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    @Environment(AppPreference.self) private var appPreference
    @Environment(LayoutState.self) private var layoutState
    @Environment(FileState.self) private var fileState
    @Bindable private var aiChatPreferences = AIChatPreferences.shared
    @AppStorage(FloatingInspectorMetrics.widthStorageKey) private var floatingInspectorWidth = FloatingInspectorMetrics.defaultWidth
    @AppStorage(InspectorControlPins.storageKey) private var controlPinsData = Data()
    @AppStorage(InspectorControlPins.expandedStorageKey) private var areUnpinnedControlsExpanded = false
    @State private var displayedHorizontalOffset: CGFloat = 0
    @State private var hasInitializedHorizontalOffset = false
    @State private var pendingHorizontalOffsetTask: Task<Void, Never>?
    @State private var isControlsHovered = false

    private var historyDisabled: Bool {
        fileState.currentActiveFile == nil
    }

    private var controlPins: InspectorControlPins {
        InspectorControlPins(storedData: controlPinsData)
    }

    private var visibleControls: [InspectorControlPins.Control] {
        let presentedControls = Set(InspectorControlPins.Control.allCases.filter { control in
            (control == .aiChat && layoutState.isAIChatIslandMode) ||
            (layoutState.isInspectorPresented && layoutState.activeInspectorTab == control.tab)
        })
        return controlPins.visibleControls(
            isExpanded: areUnpinnedControlsExpanded,
            presentedControls: presentedControls
        )
    }

    private var disclosureOpacity: Double {
#if os(macOS)
        isControlsHovered || isVoiceOverEnabled ? 1 : 0.2
#else
        1
#endif
    }

    private var disclosureTitle: String {
        String(localizable: areUnpinnedControlsExpanded
            ? .trailingControlsCollapse : .trailingControlsExpand)
    }

    private var shouldShowControls: Bool {
        shouldShowInCurrentSizeClass &&
        fileState.currentActiveFile != nil &&
        !fileState.activeCollaborationFileIsLoading
    }

    private var shouldShowInCurrentSizeClass: Bool {
#if os(iOS)
        containerHorizontalSizeClass != .compact
#else
        containerHorizontalSizeClass != .compact
#endif
    }

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var topPadding: CGFloat {
#if os(iOS)
        if containerHorizontalSizeClass == .compact {
            return 116
        }
        return shouldReserveFloatingInspectorSpace ? FloatingInspectorMetrics.controlsTopPadding : 16
#else
        16
#endif
    }

    private var trailingPadding: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 12 : 8
#else
        8
#endif
    }

    private var horizontalOffset: CGFloat {
#if os(iOS)
        floatingInspectorControlsTrailingInset
#else
        0
#endif
    }

    private var effectiveHorizontalOffset: CGFloat {
        hasInitializedHorizontalOffset ? displayedHorizontalOffset : horizontalOffset
    }

    private var floatingInspectorControlsTrailingInset: CGFloat {
#if os(iOS)
        shouldReserveFloatingInspectorSpace
        ? FloatingInspectorMetrics.controlsInset(for: CGFloat(floatingInspectorWidth))
        : 0
#else
        0
#endif
    }

    private var shouldReserveFloatingInspectorSpace: Bool {
#if os(iOS)
        guard layoutState.isInspectorPresented,
              containerHorizontalSizeClass != .compact else {
            return false
        }
        if appPreference.inspectorLayout == .floatingBar {
            return true
        }
        if #available(iOS 26.0, *),
           UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }
        return false
#else
        false
#endif
    }

    private var controlSpacing: CGFloat {
#if os(iOS)
        containerHorizontalSizeClass == .compact ? 8 : 10
#else
        10
#endif
    }

    private func isDisabled(tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return historyDisabled
            default:
                return false
        }
    }

    private var shouldOpenAIChatAsIsland: Bool {
        isCompactIOS &&
        AIChatAvailability.isAvailable &&
        aiChatPreferences.isAIEnabled &&
        !fileState.currentActiveFileIsInTrash
    }

    private func toggleAIChatPresentation() {
        if layoutState.isAIChatIslandMode {
            layoutState.isAIChatIslandMode = false
        } else if shouldOpenAIChatAsIsland {
            layoutState.isInspectorPresented = false
            layoutState.enterAIChatIsland()
        } else {
            layoutState.toggleInspector(.aiChat)
        }
    }

    var body: some View {
        if shouldShowControls {
            VStack(alignment: .center, spacing: controlSpacing) {
                ForEach(visibleControls) { control in
                    inspectorControlButton(control)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }

                if !controlPins.unpinnedControls.isEmpty {
                    disclosureButton
                }
            }
            .animation(.easeInOut(duration: 0.22), value: areUnpinnedControlsExpanded)
            .animation(.easeInOut(duration: 0.22), value: visibleControls)
#if os(macOS)
            .contentShape(Rectangle())
            .onHover { isControlsHovered = $0 }
#endif
            .background {
                // Keep Find available even when its visible button is collapsed.
                Button(String(localizable: .searchButtonTitle)) {
                    layoutState.toggleInspector(.search)
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
            }
            .padding(.top, topPadding)
            .padding(.trailing, trailingPadding + effectiveHorizontalOffset)
            .onAppear {
                syncDisplayedHorizontalOffsetWithoutAnimation()
            }
            .onDisappear {
                pendingHorizontalOffsetTask?.cancel()
                pendingHorizontalOffsetTask = nil
                hasInitializedHorizontalOffset = false
                isControlsHovered = false
            }
            .watch(value: shouldReserveFloatingInspectorSpace) { _, _ in
                scheduleAnimatedDisplayedHorizontalOffsetUpdate()
            }
            .watch(value: floatingInspectorWidth) { _, _ in
                guard shouldReserveFloatingInspectorSpace else { return }
                syncDisplayedHorizontalOffsetWithoutAnimation()
            }
            .animation(.easeOut, value: topPadding)
        }
    }

    private var disclosureButton: some View {
        InspectorDisclosureButton(
            isExpanded: $areUnpinnedControlsExpanded,
            title: disclosureTitle,
            opacity: disclosureOpacity
        )
        .contextMenu {
            Button {
                setAllControlsPinned(true)
            } label: {
                Label(.localizable(.trailingControlsPinAll), systemSymbol: .pin)
            }
            .disabled(controlPins.unpinnedControls.isEmpty)

            Button {
                setAllControlsPinned(false)
            } label: {
                Label(.localizable(.trailingControlsUnpinAll), systemSymbol: .pinSlash)
            }
            .disabled(controlPins.pinnedControls.isEmpty)
        }
    }

    private func setAllControlsPinned(_ isPinned: Bool) {
        var pins = controlPins
        pins.setAllPinned(isPinned)
        withAnimation(.easeInOut(duration: 0.18)) {
            controlPinsData = pins.storedData
        }
    }

    private func inspectorControlButton(_ control: InspectorControlPins.Control) -> some View {
        InspectorTabButton(
            tab: control.tab,
            icon: control.icon,
            title: control.title,
            isDisabled: isDisabled(tab: control.tab),
            action: control == .aiChat ? toggleAIChatPresentation : nil
        )
        .contextMenu {
            Button {
                var pins = controlPins
                pins.setPinned(!pins.isPinned(control), for: control)
                withAnimation(.easeInOut(duration: 0.18)) {
                    controlPinsData = pins.storedData
                }
            } label: {
                Label(
                    .localizable(controlPins.isPinned(control)
                        ? .trailingControlsUnpin : .trailingControlsPin),
                    systemSymbol: controlPins.isPinned(control) ? .pinSlash : .pin
                )
            }
        }
    }

    private func scheduleAnimatedDisplayedHorizontalOffsetUpdate() {
        pendingHorizontalOffsetTask?.cancel()
        pendingHorizontalOffsetTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) {
                displayedHorizontalOffset = horizontalOffset
                hasInitializedHorizontalOffset = true
            }
        }
    }

    private func syncDisplayedHorizontalOffsetWithoutAnimation() {
        pendingHorizontalOffsetTask?.cancel()
        pendingHorizontalOffsetTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedHorizontalOffset = horizontalOffset
            hasInitializedHorizontalOffset = true
        }
    }
}

private struct InspectorDisclosureButton: View {
    @Environment(CanvasPreferencesState.self) private var canvasPreferences

    @Binding var isExpanded: Bool
    let title: String
    let opacity: Double

    private var foreground: Color {
        InspectorControlContrast.prefersWhiteForeground(
            backgroundColor: canvasPreferences.viewBackgroundColor,
            isDark: canvasPreferences.theme == .dark
        ) ? .white : .black
    }

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemSymbol: .chevronDown)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 40, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.12), value: opacity)
    }
}

private struct InspectorTabButton: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(LayoutState.self) private var layoutState

    let tab: LayoutState.InspectorTab
    let icon: SFSymbol
    let title: String
    var isDisabled: Bool = false
    var action: (() -> Void)?

    private var isActive: Bool {
        if tab == .aiChat, layoutState.isAIChatIslandMode {
            return true
        }
        return layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var buttonStyleSize: ModernButtonStyleModifier.Size {
#if os(iOS)
        .regular
#else
        .large
#endif
    }

    private var iconSize: CGFloat {
        16
    }

    private var iconFrame: CGFloat {
#if os(iOS)
        return containerHorizontalSizeClass == .compact ? 28 : 24
#else
        return 24
#endif
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            if let action {
                action()
            } else {
                layoutState.toggleInspector(tab)
            }
        } label: {
            Label(title, systemSymbol: icon)
                .font(.system(size: iconSize))
                .frame(width: iconFrame, height: iconFrame)
        }
        .labelStyle(.iconOnly)
        .modernButtonStyle(
            style: isActive ? .glassProminent : .glass,
            size: buttonStyleSize,
            shape: .circle
        )
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }
}

private extension InspectorControlPins.Control {
    var tab: LayoutState.InspectorTab {
        switch self {
            case .preference: .preference
            case .search: .search
            case .library: .library
            case .history: .history
            case .presentation: .presentation
            case .aiChat: .aiChat
        }
    }

    var icon: SFSymbol {
        switch self {
            case .preference: .sliderHorizontal3
            case .search: .magnifyingglass
            case .library: .book
            case .history: .clockArrowCirclepath
            case .presentation: .play
            case .aiChat: .sparkles
        }
    }

    var title: String {
        switch self {
            case .preference: String(localizable: .canvasPreferencesTitle)
            case .search: String(localizable: .searchButtonTitle)
            case .library: String(localizable: .librariesTitle)
            case .history: String(localizable: .checkpoints)
            case .presentation: String(localizable: .presentationTitle)
            case .aiChat: "AI Chat"
        }
    }
}
