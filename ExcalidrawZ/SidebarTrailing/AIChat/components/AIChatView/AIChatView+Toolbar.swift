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
            ToolbarItemGroup(placement: .destructiveAction) {
                Button {
                    layoutState.enterAIChatIsland()
                } label: {
                    Label(.localizable(.aiChatButtonIslandMode), systemSymbol: .menubarDockRectangle)
                }
                .disabled(fileState.currentActiveFileIsInTrash || shouldBlockAIForNonAppStoreMac)
                .help(String(localizable: .aiChatButtonIslandModeHelp))
            }
            
            // This work...
            ToolbarItemGroup(placement: .principal) {
                Spacer()
            }
            
#if os(macOS)
            if #available(macOS 26.0, *) {
                // Not working...
                ToolbarSpacer(.fixed)
            }
#endif
            
#if os(macOS)
            InspectorHeaderToolbar(
                title: String(localizable: .aiChatTitle),
                isInspectorPresented: layoutState.isInspectorPresented
            )
#endif
            
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {} label: {
                        Label(.localizable( .aiChatButtonCreditsCount(creditsDisplayText)),
                            systemSymbol: .sparkles
                        )
                    }
                    .disabled(true)
                    
                    Divider()
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingWelcomeManually = true
                        }
                    } label: {
                        Label(.localizable(.aiChatButtonShowWelcome), systemSymbol: .sparkles)
                    }
                    
#if os(macOS)
                    if #available(macOS 14.0, *) {
                        OpenSettingsMenuItem(deepLinkTo: .ai)
                    } else {
                        // Pre-`openSettings` env fallback — NSApp.sendAction
                        // path. Older macOS doesn't carry the macOS 26+ runtime
                        // "Please use SettingsLink" warning.
                        Button {
                            SettingsRouter.shared.requestOpen(.ai)
                        } label: {
                            Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
                        }
                    }
#else
                    Button {
                        SettingsRouter.shared.requestOpen(.ai)
                    } label: {
                        Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
                    }
#endif
                    
#if DEBUG
                    Divider()
                    
                    Menu {
                        Toggle("Render counters", isOn: $aiChatRenderDebug.isEnabled)
                        Toggle("Hide message list", isOn: $aiChatRenderDebug.hideMessageList)
                        Toggle("Minimal prompt input", isOn: $aiChatRenderDebug.useMinimalPromptInput)
                        Toggle("Hide prompt action bar", isOn: $aiChatRenderDebug.hidePromptActionBar)
                        Toggle("Hide generating effect", isOn: $aiChatRenderDebug.hideGeneratingEffect)
                        Toggle("Stack scroll host", isOn: $aiChatRenderDebug.useStackMessageListHost)
                        
                        Divider()
                        
                        Button {
                            aiChatRenderDebug.reset()
                        } label: {
                            Label("Reset flags", systemSymbol: .arrowCounterclockwise)
                        }
                    } label: {
                        Label("Render debug", systemImage: "waveform.path.ecg")
                    }
#endif
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label(.localizable(.aiChatButtonClearChat), systemSymbol: .trash)
                    }
                    // Disable when there's no conversation to clear, so the
                    // user doesn't get a confirmationDialog for a no-op.
                    .disabled(fileState.aiChatConversationID == nil)
                } label: {
                    Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                }
                .menuIndicator(.hidden)
            }
        }
    }
    
    
}
