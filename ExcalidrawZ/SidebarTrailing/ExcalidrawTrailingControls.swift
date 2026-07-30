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

    @EnvironmentObject private var appPreference: AppPreference
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared
    @AppStorage(FloatingInspectorMetrics.widthStorageKey) private var floatingInspectorWidth = FloatingInspectorMetrics.defaultWidth
    @State private var displayedHorizontalOffset: CGFloat = 0
    @State private var hasInitializedHorizontalOffset = false
    @State private var pendingHorizontalOffsetTask: Task<Void, Never>?

    private var historyDisabled: Bool {
        fileState.currentActiveFile == nil
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
            VStack(alignment: .trailing, spacing: controlSpacing) {
                InspectorTabButton(
                    tab: .preference,
                    icon: .sliderHorizontal3,
                    title: String(localizable: .canvasPreferencesTitle),
                    isDisabled: isDisabled(tab: .preference)
                )

                InspectorTabButton(
                    tab: .search,
                    icon: .magnifyingglass,
                    title: String(localizable: .searchButtonTitle),
                    isDisabled: isDisabled(tab: .search)
                )
                .keyboardShortcut("f", modifiers: .command)

                InspectorTabButton(
                    tab: .library,
                    icon: .book,
                    title: String(localizable: .librariesTitle),
                    isDisabled: isDisabled(tab: .library)
                )

                InspectorTabButton(
                    tab: .history,
                    icon: .clockArrowCirclepath,
                    title: String(localizable: .checkpoints),
                    isDisabled: isDisabled(tab: .history)
                )

                InspectorTabButton(
                    tab: .presentation,
                    icon: .play,
                    title: String(localizable: .presentationTitle),
                    isDisabled: isDisabled(tab: .presentation)
                )

                InspectorTabButton(
                    tab: .aiChat,
                    icon: .sparkles,
                    title: "AI Chat",
                    isDisabled: isDisabled(tab: .aiChat),
                    action: toggleAIChatPresentation
                )

#if DEBUG
//                InspectorTabButton(
//                    tab: .debug,
//                    icon: .ladybug,
//                    title: "Debug",
//                    isDisabled: isDisabled(tab: .debug)
//                )
#endif
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

private struct InspectorTabButton: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @EnvironmentObject private var layoutState: LayoutState

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
