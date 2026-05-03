//
//  AIChatView.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/09.
//

import ChocofordUI
import LLMCore
import LLMKit
import SFSafeSymbols
import SwiftUI

struct AIChatView: View {
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject

    @State private var conversationID: String?
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    @State private var lastBottomID: String?
    @State private var isPinnedToBottom: Bool = true
    @State private var scrollToBottomRequest = ScrollToBottomRequest()

    var conversation: Conversation? {
        llmState.conversations.value?.first { $0.id == conversationID }
    }

    private var streamingState: LLMStreamingStateObject? {
        guard let conversationID else { return nil }
        return llmState.streamingStore.streamIfExists(for: conversationID)
            as? LLMStreamingStateObject
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            if let conversation, !conversation.messages.isEmpty {
                messageList(messages: conversation.messages)
            } else {
                emptyPlaceholder()
            }

            PromptInputView(conversationID: $conversationID)
        }
        .padding(.bottom, 6)
        .toolbar(content: toolbar)
        .task {
            await llmState.refreshConversations()
        }
    }

    @ViewBuilder
    private func emptyPlaceholder() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("AI Chat Assistant")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Text("Ask questions about your diagrams or get help with Excalidraw features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messageList(messages: [ChatMessage]) -> some View {
        let bottomID = streamingState?.id ?? messages.last?.id
        ChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest
        ) {
            messageListRows(messages: messages)
        }
        .overlay(alignment: .bottom) {
            if !isPinnedToBottom {
                Button {
                    requestScrollToBottom(animated: true)
                    isPinnedToBottom = true
                } label: {
                    Image(systemSymbol: .arrowDown)
                }
                .modernButtonStyle(style: .glass, shape: .circle)
                .transition(.opacity)
                .padding()
            }
        }
        .onAppear {
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: bottomID) { _ in
            requestScrollToBottomIfNeeded(bottomID)
        }
    }

    @ViewBuilder
    private func messageListRows(messages: [ChatMessage]) -> some View {
        SwiftUI.Group {
            StaticMessageList(messages: messages, onRegenerate: regenerateMessage)

            if let streamingState, shouldShowStreamingMessage(streamingState, messages: messages) {
                StreamingMessageRow(
                    stream: streamingState,
                    onRegenerate: regenerateMessage,
                    useStreamBuffering: true,
                    onStreamUpdate: {
                        guard isPinnedToBottom else { return }
                        requestScrollToBottom(animated: false)
                    }
                )
                .id(streamingState.id)
            }
        }
    }
    
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: .destructiveAction) {
                
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
        
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: .automatic) {
               
            }
        }
    }

    private func regenerateMessage(messageID: String) {
        guard let conversationID else { return }
        Task {
            do {
                try await llmState.regenerateMessage(
                    in: conversationID,
                    fromMessageID: messageID,
                    model: .gpt4oMini,
                    stream: true
                )
            } catch {
                print("Failed to regenerate message: \(error)")
            }
        }
    }

    private func shouldShowStreamingMessage(
        _ stream: LLMStreamingStateObject,
        messages: [ChatMessage]
    ) -> Bool {
        if !stream.isFinished { return true }
        guard let lastID = messages.last?.id else { return !stream.content.isEmpty }
        return lastID != stream.id
    }

    private func requestScrollToBottomIfNeeded(_ newBottomID: String?) {
        guard let newBottomID else { return }
        guard newBottomID != lastBottomID else { return }
        lastBottomID = newBottomID
        guard isPinnedToBottom else { return }
        requestScrollToBottom(animated: false)
    }

    private func requestScrollToBottom(animated: Bool) {
        scrollToBottomRequest = ScrollToBottomRequest(
            token: scrollToBottomRequest.token + 1,
            animated: animated
        )
    }
}

private struct StaticMessageList: View, Equatable {
    let messages: [ChatMessage]
    let onRegenerate: ((String) -> Void)?

    static func == (lhs: StaticMessageList, rhs: StaticMessageList) -> Bool {
        guard lhs.messages.count == rhs.messages.count else { return false }
        return zip(lhs.messages, rhs.messages).allSatisfy { $0.id == $1.id }
    }

    var body: some View {
        ForEach(messages) { message in
            ChatScrollRow {
                MessageView(message: message, displayText: nil, onRegenerate: onRegenerate)
            }
        }
    }
}

private struct StreamingMessageRow: View {
    @ObservedObject var stream: LLMStreamingStateObject
    var onRegenerate: ((String) -> Void)?
    var useStreamBuffering: Bool = true
    var onStreamUpdate: (() -> Void)?
    @StateObject private var buffer = StreamTextBuffer()

    var message: ChatMessage {
        if let stepType = stream.stepType {
            return .agentStep(
                .init(
                    id: UUID(uuidString: stream.id) ?? UUID(),
                    stepNumber: 0,
                    type: stepType,
                    content: stream.content,
                    timestamp: Date()
                )
            )
        } else {
            return .content(
                .init(
                    id: stream.id,
                    role: .assistant,
                    content: stream.content,
                    files: stream.files,
                    usage: nil
                )
            )
        }
    }

    var body: some View {
        if useStreamBuffering {
            bufferedBody
        } else {
            unbufferedBody
        }
    }

    private var bufferedBody: some View {
        ChatScrollRow {
            MessageView(
                message: message,
                displayText: buffer.displayText,
                onRegenerate: onRegenerate,
                isActiveStep: stream.stepType != nil && !stream.isFinished
            )
        }
        .onAppear {
            buffer.reset(with: stream.content)
        }
        .onChange(of: stream.id) { _ in
            buffer.reset(with: stream.content)
        }
        .onChange(of: stream.content) { newValue in
            buffer.ingest(newValue)
            onStreamUpdate?()
        }
        .onChange(of: stream.isFinished) { _ in
            buffer.finalize()
        }
    }

    private var unbufferedBody: some View {
        ChatScrollRow {
            MessageView(
                message: message,
                displayText: nil,
                onRegenerate: onRegenerate,
                isActiveStep: stream.stepType != nil && !stream.isFinished
            )
        }
        .onChange(of: stream.content) { _ in
            onStreamUpdate?()
        }
    }
}

@MainActor
private final class StreamTextBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var pendingText = ""
    private var lastFlushedText = ""
    private var flushTask: Task<Void, Never>?

    private let flushIntervalNanos: UInt64 = 120_000_000
    private let minDeltaCharacters = 24
    private let maxAnimatedDeltaCharacters = 12

    func reset(with text: String) {
        cancelFlush()
        pendingText = text
        lastFlushedText = text
        displayText = text
    }

    func ingest(_ text: String) {
        guard text != pendingText else { return }
        pendingText = text
        let delta = abs(text.count - lastFlushedText.count)
        if delta >= minDeltaCharacters || text.hasSuffix("\n") {
            flush(animated: false)
        } else {
            scheduleFlush()
        }
    }

    func finalize() {
        flush(animated: false)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: flushIntervalNanos)
            self.flush(animated: true)
        }
    }

    private func flush(animated: Bool) {
        guard pendingText != lastFlushedText else {
            cancelFlush()
            return
        }
        let text = pendingText
        let delta = abs(text.count - lastFlushedText.count)
        lastFlushedText = text
        cancelFlush()
        if animated, delta <= maxAnimatedDeltaCharacters {
            withAnimation(.easeOut(duration: 0.12)) {
                displayText = text
            }
        } else {
            displayText = text
        }
    }

    private func cancelFlush() {
        flushTask?.cancel()
        flushTask = nil
    }
}

#if DEBUG
    #Preview {
        AIChatView()
            .frame(width: 250, height: 600)
            .llmProvider(
                client: .shared,
                persistenceProvider: nil,
                lagacy: true
            )
    }
#endif
