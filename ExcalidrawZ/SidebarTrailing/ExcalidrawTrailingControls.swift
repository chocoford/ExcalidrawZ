//
//  ExcalidrawTrailingControls.swift
//  ExcalidrawZ
//
//  Created by OpenAI on 2025/2/14.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct ExcalidrawTrailingControls: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    private var historyDisabled: Bool {
        fileState.currentActiveFile == nil
    }

    private func isDisabled(tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return historyDisabled
            default:
                return false
        }
    }

    var body: some View {
        if containerHorizontalSizeClass != .compact, fileState.currentActiveFile != nil {
            VStack(alignment: .trailing, spacing: 10) {
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
                    tab: .aiChat,
                    icon: .sparkles,
                    title: "AI Chat",
                    isDisabled: isDisabled(tab: .aiChat)
                )

#if DEBUG
                InspectorTabButton(
                    tab: .debug,
                    icon: .ladybug,
                    title: "Debug",
                    isDisabled: isDisabled(tab: .debug)
                )
#endif
            }
            .padding(.top, 16)
            .padding(.trailing, 8)
        }
    }
}

private struct InspectorTabButton: View {
    @EnvironmentObject private var layoutState: LayoutState

    let tab: LayoutState.InspectorTab
    let icon: SFSymbol
    let title: String
    var isDisabled: Bool = false

    private var isActive: Bool {
        layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
        }
        .labelStyle(.iconOnly)
        .modernButtonStyle(
            style: isActive ? .glassProminent : .glass,
            size: .large,
            shape: .circle
        )
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }
}
