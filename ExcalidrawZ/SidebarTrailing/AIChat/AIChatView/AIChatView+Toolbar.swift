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
            if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .destructiveAction) {
                    Button {
                        layoutState.enterAIChatIsland()
                    } label: {
                        Label("Float as island", systemSymbol: .menubarDockRectangle)
                    }
                    .disabled(fileState.currentActiveFileIsInTrash)
                    .help("Float chat as a draggable island over the editor")
                }
                
                // This work...
                ToolbarItemGroup(placement: .principal) {
                    Spacer()
                }
                
                // Not working...
                ToolbarSpacer(.fixed)
            }
            
            InspectorHeaderToolbar(
                title: "AI Chat",
                isInspectorPresented: layoutState.isInspectorPresented
            )
            
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {} label: {
                        Label("\(creditsDisplayText) credits", systemSymbol: .sparkles)
                    }
                    .disabled(true)

                    Divider()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingWelcomeManually = true
                        }
                    } label: {
                        Label("Show welcome", systemSymbol: .sparkles)
                    }

                    if #available(macOS 14.0, iOS 17.0, *) {
                        OpenSettingsMenuItem(deepLinkTo: .ai)
                    } else {
                        // Pre-`openSettings` env fallback — NSApp.sendAction
                        // path. Older macOS doesn't carry the macOS 26+ runtime
                        // "Please use SettingsLink" warning.
                        Button {
                            SettingsRouter.shared.requestOpen(.ai)
                        } label: {
                            Label("Settings…", systemSymbol: .gearshape)
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear chat", systemSymbol: .trash)
                    }
                    // Disable when there's no conversation to clear, so the
                    // user doesn't get a confirmationDialog for a no-op.
                    .disabled(fileState.aiChatConversationID == nil)
                } label: {
                    Label("More", systemSymbol: .ellipsis)
                }
                .menuIndicator(.hidden)
            }
        }
    }
    

}
