//
//  AIChatView+Toolbar.swift
//  ExcalidrawZ
//

import ChocofordUI
import SFSafeSymbols
import SwiftUI

extension AIChatView {
    @MainActor @ToolbarContentBuilder
    func toolbar() -> some ToolbarContent {
        if layoutState.isInspectorPresented {
#if os(macOS)
            ToolbarItemGroup(placement: .destructiveAction) {
                islandModeButton
            }
#else
            ToolbarItemGroup(placement: .topBarLeading) {
                islandModeButton
            }
#endif

#if os(iOS)
            if containerHorizontalSizeClass != .compact {
                InspectorHeaderToolbar(
                    title: String(localizable: .aiChatTitle),
                    isInspectorPresented: layoutState.isInspectorPresented
                )
            }
#else
            // This work...
            ToolbarItemGroup(placement: .principal) {
                Spacer()
            }

            if #available(macOS 26.0, *) {
                // Not working...
                ToolbarSpacer(.fixed)
            }

            InspectorHeaderToolbar(
                title: String(localizable: .aiChatTitle),
                isInspectorPresented: layoutState.isInspectorPresented
            )
#endif
            
            ToolbarItemGroup(placement: .automatic) {
                aiChatMoreMenu
            }
        }

#if os(iOS)
        if containerHorizontalSizeClass == .compact,
           !layoutState.isInspectorPresented {
            ToolbarItemGroup(placement: .topBarTrailing) {
                aiChatMoreMenu
            }
        }
#endif
    }

    private var aiChatMoreMenu: some View {
        Menu {
            // Explicit sibling views avoid ContentBuilder inferring TupleContent.
            TupleView((
                aiChatCreditsMenuItem,
                Divider(),
                aiChatWelcomeMenuItem,
                aiChatSettingsMenuItems,
                Divider(),
                aiChatClearMenuItem
            ))
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
        }
        .menuIndicator(.hidden)
    }

    private var aiChatCreditsMenuItem: some View {
        Button {} label: {
            Label(.localizable(.aiChatButtonCreditsCount(creditsDisplayText)),
                  systemSymbol: .sparkles)
        }
        .disabled(true)
    }

    private var aiChatWelcomeMenuItem: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingWelcomeManually = true
            }
        } label: {
            Label(.localizable(.aiChatButtonShowWelcome), systemSymbol: .sparkles)
        }
    }

    private var aiChatSettingsMenuItems: some View {
#if os(macOS)
        // Use ordinary control flow and erase the macOS 14-only types before returning.
        if #available(macOS 14.0, *) {
            return AnyView(TupleView((
                OpenMCPSettingsMenuItem(deepLinkTo: .ai),
                OpenSettingsMenuItem(deepLinkTo: .ai, aiSettingsRoute: .settings)
            )))
        } else {
            return AnyView(TupleView((
                aiChatMCPSettingsMenuItem,
                aiChatAISettingsMenuItem
            )))
        }
#else
        return aiChatAISettingsMenuItem
#endif
    }

#if os(macOS)
    private var aiChatMCPSettingsMenuItem: some View {
        Button {
            presentMCPSettings()
        } label: {
            Label(.localizable(.aiChatButtonMCPSettings), systemSymbol: .serverRack)
        }
    }
#endif

    private var aiChatAISettingsMenuItem: some View {
        Button {
            presentAISettings()
        } label: {
            Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
        }
    }

    private var aiChatClearMenuItem: some View {
        Button(role: .destructive) {
            isConfirmingClear = true
        } label: {
            Label(.localizable(.aiChatButtonClearChat), systemSymbol: .trash)
        }
        .disabled(fileState.aiChatConversationID == nil)
    }

    @ViewBuilder
    private var islandModeButton: some View {
        Button {
#if os(iOS)
            if containerHorizontalSizeClass == .compact {
                layoutState.enterCompactAIChatInputEditing()
            } else {
                layoutState.enterAIChatIsland()
            }
#else
            layoutState.enterAIChatIsland()
#endif
        } label: {
            Label(.localizable(.aiChatButtonIslandMode), systemSymbol: .menubarDockRectangle)
        }
        .disabled(fileState.currentActiveFileIsInTrash || !isAIAvailable || !prefs.isAIEnabled)
        .help(String(localizable: .aiChatButtonIslandModeHelp))
    }

    private func presentAISettings() {
        SettingsRouter.shared.pendingRoute = .ai
        SettingsRouter.shared.pendingAISettingsRoute = .settings
#if os(iOS)
        isAISettingsSheetPresented = true
#else
        SettingsRouter.shared.requestOpen(.ai)
#endif
    }

    private func presentMCPSettings() {
        SettingsRouter.shared.pendingRoute = .ai
        SettingsRouter.shared.pendingAISettingsRoute = .mcp
#if os(iOS)
        isAISettingsSheetPresented = true
#else
        SettingsRouter.shared.requestOpen(.ai)
#endif
    }
}
