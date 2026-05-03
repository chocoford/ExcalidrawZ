//
//  PromptInputView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/10/26.
//

import SwiftUI

import ChocofordUI
import LLMKit
import LLMCore

struct ExcalidrawChatInvocationContext: ChatInvocationContext {
    var currentFileData: Data?
    var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    var selectedElementIDs: [String]?
}

struct PromptInputView: View {
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var fileState: FileState
    
    @Binding var conversationID: String?
    
    init(conversationID: Binding<String?>) {
        self._conversationID = conversationID
    }

    
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var selectedModel: SupportedModel = .gpt4oMini

    @FocusState private var isInputFocused: Bool
    
    var conversation: Conversation? {
        guard let conversationID else { return nil }
        return llmState.getConversation(by: conversationID)
    }
    
    var currentFileData: Data? {
        get async throws {
            let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                switch fileState.currentActiveFile {
                    case .collaborationFile:
                        .collaboration
                    default:
                        .normal
                }
            }()
            return try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: canvasTarget
            )
        }
    }
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content()
                .glassEffect(in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .gray.opacity(0.2), radius: 4)
//                .background {
//                    RoundedRectangle(cornerRadius: 16)
//                        .fill(.background)
//                        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
//                }
                .padding(8)
        } else {
            content()
                .padding(8)
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        
        VStack(spacing: 0) {
            if #available(macOS 15.0, iOS 18.0, *) {
                AutoGrowTextEditor(
                    text: $inputText,
                    placeholder: Text("Type a message...")
                )
                .focused($isInputFocused)
            } else {
                TextEditor(text: $inputText)
                    .frame(height: 160)
                    .focused($isInputFocused)
            }
            
            HStack {
                Spacer()
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemSymbol: .arrowUp)
                }
                .modernButtonStyle(style: .glass, shape: .circle)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 6)
            .padding(.horizontal, 6)
        }
    }
    
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let prompt = trimmedText
        inputText = ""
        isLoading = true
        
        let newConversationID = UUID().uuidString
 
        Task {
            do {
                await MainActor.run {
                    ExcalidrawCoordinatorRegistry.shared.update(
                        normal: fileState.excalidrawWebCoordinator,
                        collaboration: fileState.excalidrawCollaborationWebCoordinator
                    )
                }
                let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                    switch fileState.currentActiveFile {
                        case .collaborationFile:
                            .collaboration
                        default:
                            .normal
                    }
                }()
                let selectedElementIDs: [String]? = await MainActor.run {
                    let coordinator: ExcalidrawCanvasView.Coordinator? = switch canvasTarget {
                        case .normal:
                            fileState.excalidrawWebCoordinator
                        case .collaboration:
                            fileState.excalidrawCollaborationWebCoordinator
                    }
                    let ids = coordinator?.selectedElementIDs ?? []
                    return ids.isEmpty ? nil : ids
                }
                let context = try await ExcalidrawChatInvocationContext(
                    currentFileData: currentFileData,
                    canvasTarget: canvasTarget,
                    selectedElementIDs: selectedElementIDs
                )
                
                // If this is a new conversation, create it with ReAct agent config
                if self.conversation == nil {
                    self.conversationID = newConversationID
                    // - Do not use a colon before tool calls. Your tool calls may not be shown directly in the output, so text like "Let me read the file:" followed by a read tool call should just be "Let me read the file." with a period.
                    try await llmState.createConversation(
                        id: newConversationID,
                        type: .custom("File"),
                        model: selectedModel,
                        agentConfig: .react(
                            tools: ["web_search", "web_fetch", "read_file", "calculator", "datetime", "adjust_elements", "final_answer"],
                            systemPrompt: """
                                
                                """
                        ),
                        messages: [.content(.init(role: .user, content: prompt))],
                        context: context
                    )
                } else {
                    // Otherwise just send the message
                    try await llmState.sendMessage(
                        to: self.conversationID!,
                        model: selectedModel,
                        message: .content(.init(role: .user, content: prompt)),
                        context: context
                    )
                }
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    print("Error: \(error)")
                    isLoading = false
                }
            }
        }
        
    }
}
