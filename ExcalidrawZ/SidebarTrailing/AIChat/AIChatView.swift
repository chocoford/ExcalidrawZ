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
        let isStreamingActive: Bool = {
            guard let stream = streamingState else { return false }
            return shouldShowStreamingMessage(stream, messages: messages)
        }()
        ChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            followBottom: isStreamingActive
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
        let layout = makeRowLayout(messages: messages)

        StaticGroupsView(groups: layout.staticGroups, onRegenerate: regenerateMessage)
            .equatable()

        if let liveStream = layout.liveStream {
            ChatScrollRow {
                LiveAssistantRoundView(
                    committedMessages: layout.liveCommittedRound,
                    stream: liveStream,
                    onRegenerate: regenerateMessage,
                    // `ChatScrollView`'s `followBottom` is on while streaming —
                    // it auto-scrolls on every contentHeight change. We don't
                    // need a per-chunk scroll request here too; that just
                    // queues up redundant scrolls before layout has settled.
                    onStreamUpdate: nil
                )
            }
        }
    }

    /// Partition committed messages into static groups + (optional) live round.
    /// If a stream is in flight, the trailing assistantRound (if any) is the
    /// live round — its committed messages are pulled aside so `LiveAssistantRoundView`
    /// can splice the in-flight inflight message onto the end.
    private func makeRowLayout(messages: [ChatMessage]) -> RowLayout {
        let allGroups = groupMessages(messages)
        guard
            let liveStream = streamingState,
            shouldShowStreamingMessage(liveStream, messages: messages)
        else {
            return RowLayout(staticGroups: allGroups, liveStream: nil, liveCommittedRound: [])
        }
        if let last = allGroups.last, case .assistantRound(_, let msgs) = last {
            return RowLayout(
                staticGroups: Array(allGroups.dropLast()),
                liveStream: liveStream,
                liveCommittedRound: msgs
            )
        }
        return RowLayout(staticGroups: allGroups, liveStream: liveStream, liveCommittedRound: [])
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
                let agentConfig = try await LLMClient.shared.getDomainAgentConfig(agentID: "excalidraw-canvas")
                try await llmState.regenerateMessage(
                    in: conversationID,
                    fromMessageID: messageID,
                    model: agentConfig.defaultModel,
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

// MARK: - Grouping

private struct RowLayout {
    let staticGroups: [MessageGroup]
    let liveStream: LLMStreamingStateObject?
    let liveCommittedRound: [ChatMessage]
}

/// A single chat row in the timeline. Multiple consecutive assistant + tool
/// messages from one agent turn collapse into one `assistantRound`, so the user
/// sees one logical AI reply per question instead of N bubbles.
private enum MessageGroup: Identifiable {
    case user(ChatMessageContent)
    case assistantRound(id: String, messages: [ChatMessage])
    case loading(UUID)
    case error(UUID, String)

    var id: String {
        switch self {
            case .user(let c): return c.id
            case .assistantRound(let id, _): return id
            case .loading(let id): return id.uuidString
            case .error(let id, _): return id.uuidString
        }
    }
}

/// Walk the message list and bucket it into [user | assistantRound | loading | error].
/// system/developer messages are scaffolding and dropped here.
private func groupMessages(_ messages: [ChatMessage]) -> [MessageGroup] {
    var result: [MessageGroup] = []
    var pending: [ChatMessage] = []

    func flushPending() {
        guard !pending.isEmpty else { return }
        result.append(.assistantRound(id: pending.last!.id, messages: pending))
        pending = []
    }

    for message in messages {
        switch message {
            case .content(let c):
                switch c.role {
                    case .user:
                        flushPending()
                        result.append(.user(c))
                    case .assistant, .tool:
                        pending.append(message)
                    case .system, .developer:
                        continue
                }
            case .loading(let id):
                flushPending()
                result.append(.loading(id))
            case .error(let id, let msg):
                flushPending()
                result.append(.error(id, msg))
        }
    }
    flushPending()
    return result
}

// MARK: - Round splitting (intermediate steps + final answer)

private struct RoundSplit {
    var intermediate: [ChatMessage]
    var finalText: String?
    /// ID of the message that produced the final answer — used for regenerate.
    var finalSourceID: String?
}

private func splitRound(_ messages: [ChatMessage]) -> RoundSplit {
    for i in messages.indices.reversed() {
        guard case .content(let c) = messages[i] else { continue }
        // Plain final answer: assistant + no toolCalls + non-empty content.
        if c.isFinalAnswer {
            return RoundSplit(
                intermediate: Array(messages[..<i]),
                finalText: c.content,
                finalSourceID: c.id
            )
        }
        // `final_answer` tool-call form: extract user-facing text from its args.
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return RoundSplit(
                intermediate: Array(messages[..<i]),
                finalText: parseFinalAnswerArgs(finalCall.arguments),
                finalSourceID: c.id
            )
        }
    }
    return RoundSplit(intermediate: messages, finalText: nil, finalSourceID: nil)
}

/// Pull the user-facing text out of `final_answer`'s JSON arguments.
/// Tries the strict parse first; falls back to a lenient scan so partial args
/// (mid-stream) still yield readable text.
private func parseFinalAnswerArgs(_ arguments: String) -> String {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidateKeys = ["text", "answer", "content", "final_answer", "result", "message", "response"]

    if let data = trimmed.data(using: .utf8) {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in candidateKeys {
                if let value = dict[key] as? String { return value }
            }
        }
        if let plain = try? JSONDecoder().decode(String.self, from: data) {
            return plain
        }
    }
    for key in candidateKeys {
        if let value = lenientExtract(trimmed, key: key) {
            return value
        }
    }
    return arguments
}

/// Find `"key": "..."` and return the value, stopping at the first unescaped
/// `"` or end-of-string. Tolerates truncated JSON during streaming.
private func lenientExtract(_ s: String, key: String) -> String? {
    let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\""
    guard let range = s.range(of: pattern, options: .regularExpression) else { return nil }
    var i = range.upperBound
    var result = ""
    while i < s.endIndex {
        let c = s[i]
        if c == "\\" {
            i = s.index(after: i)
            guard i < s.endIndex else { break }
            switch s[i] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                default: result.append(s[i])
            }
            i = s.index(after: i)
            continue
        }
        if c == "\"" {
            return result
        }
        result.append(c)
        i = s.index(after: i)
    }
    // Stream truncated mid-value — return what we have so far.
    return result.isEmpty ? nil : result
}

// MARK: - Group rendering

private struct StaticGroupsView: View, Equatable {
    let groups: [MessageGroup]
    let onRegenerate: ((String) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groups.count == rhs.groups.count else { return false }
        return zip(lhs.groups, rhs.groups).allSatisfy { $0.id == $1.id }
    }

    var body: some View {
        ForEach(groups) { group in
            ChatScrollRow {
                renderGroup(group)
            }
        }
    }

    @MainActor @ViewBuilder
    private func renderGroup(_ group: MessageGroup) -> some View {
        switch group {
            case .user(let c):
                MessageView(message: .content(c))
            case .loading(let id):
                MessageView(message: .loading(id))
            case .error(let id, let msg):
                MessageView(message: .error(id, msg))
            case .assistantRound(_, let messages):
                AssistantRoundView(messages: messages, onRegenerate: onRegenerate)
        }
    }
}

/// One agent turn rendered Xcode-style: flat, no AI-side bubble. All assistant
/// prose (intermediate prefaces and final answer) uses one uniform body/primary
/// style — only tool cards and tool results visually distinguish themselves.
/// Final answer (plain content or `final_answer` tool args) shows as plain
/// selectable text. A single action row sits at the bottom — actions are
/// per-round, never per-message.
private struct AssistantRoundView: View {
    let messages: [ChatMessage]
    /// Which message inside this round is currently streaming, if any.
    /// Used only to decide whether to show actions / shimmer — text smoothing
    /// is owned by `SmoothStreamingText` itself.
    let inflightID: String?
    let isActive: Bool
    let onRegenerate: ((String) -> Void)?

    init(
        messages: [ChatMessage],
        inflightID: String? = nil,
        isActive: Bool = false,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.messages = messages
        self.inflightID = inflightID
        self.isActive = isActive
        self.onRegenerate = onRegenerate
    }

    var body: some View {
        let split = splitRound(messages)
        let isLiveFinal = inflightID != nil && split.finalSourceID == inflightID
        // While streaming, hide trivially-short partial content. Otherwise the
        // user sees a single character pop in and then "stall" for ~1 s while
        // the next batch buffers — feels like the model froze. Wait until either
        // the snippet is long enough to read as intentional, or it ends at a
        // sentence boundary, then drop the curtain.
        let displayedFinalText: String? = {
            guard isLiveFinal, let text = split.finalText else { return split.finalText }
            return Self.isMeaningfulLiveSnippet(text) ? text : nil
        }()
        // Actions only on committed finals (never while streaming).
        let actionsSourceID: String? = {
            guard !isLiveFinal, let id = split.finalSourceID, displayedFinalText?.isEmpty == false else {
                return nil
            }
            return id
        }()
        let structureSignature = makeStructureSignature(
            intermediate: split.intermediate,
            hasFinal: displayedFinalText?.isEmpty == false,
            actionsVisible: actionsSourceID != nil
        )

        VStack(alignment: .leading, spacing: 10) {
            ForEach(split.intermediate) { msg in
                intermediateStep(msg, isActive: isActive && msg.id == inflightID)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let text = displayedFinalText, !text.isEmpty {
                SmoothStreamingText(target: text, isStreaming: isLiveFinal && isActive)
                    .textSelection(.enabled)
                    .transition(.opacity)
            } else if isActive && split.intermediate.isEmpty {
                LoadingMessageRow()
                    .transition(.opacity)
            }
            if let sourceID = actionsSourceID, let text = displayedFinalText {
                actionRow(text: text, sourceID: sourceID)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.35), value: structureSignature)
    }

    /// Threshold for unveiling streaming content. Below this we keep the loading
    /// row visible — accumulating in the background — so users never see a tease
    /// like a single character that then sits motionless for a beat. Either we
    /// have enough chars to read as intentional, or we hit a sentence-ending
    /// punctuation, or the stream finishes (handled by the `isLiveFinal` flip).
    private static let liveSnippetMinChars = 30
    private static let liveSnippetTerminators: Set<Character> = [
        ".", "!", "?", "\n", ":", ";",
        "。", "！", "？", "：", "；",
    ]

    private static func isMeaningfulLiveSnippet(_ text: String) -> Bool {
        if text.count >= liveSnippetMinChars { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, liveSnippetTerminators.contains(last) {
            return true
        }
        return false
    }

    /// Compact signature of the round's *structure* (which steps exist, whether
    /// final/actions are visible). Drives `.animation(value:)` so SwiftUI animates
    /// insertions/removals. Body content changes inside cards (eg streaming text)
    /// are *not* captured — those animate at their own cadence.
    private func makeStructureSignature(
        intermediate: [ChatMessage],
        hasFinal: Bool,
        actionsVisible: Bool
    ) -> String {
        let stepIDs = intermediate.map(\.id).joined(separator: ",")
        return "\(stepIDs)|f=\(hasFinal)|a=\(actionsVisible)"
    }

    @MainActor @ViewBuilder
    private func intermediateStep(_ message: ChatMessage, isActive: Bool) -> some View {
        if case .content(let c) = message {
            if c.isToolResult {
                ToolResultCard(content: c)
            } else if c.role == .assistant {
                let rawPreface = c.content ?? ""
                // Same anti-tease rule as the final answer: while this step is
                // the live one, suppress micro-snippets so the toolCallCard
                // appears alone first instead of "I" floating above it.
                let preface: String = {
                    guard isActive else { return rawPreface }
                    return Self.isMeaningfulLiveSnippet(rawPreface) ? rawPreface : ""
                }()
                let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
                VStack(alignment: .leading, spacing: 6) {
                    // All assistant prose uses the same body/primary style — same
                    // as the final answer below — so the visual treatment doesn't
                    // shift mid-stream when toolCalls arrive and re-classify the
                    // message as "intermediate".
                    if !preface.isEmpty {
                        SmoothStreamingText(target: preface, isStreaming: isActive)
                            .textSelection(.enabled)
                    }
                    ForEach(nonFinalCalls, id: \.id) { call in
                        ToolCallCard(call: call, isActive: isActive)
                    }
                }
            }
        }
    }

    @MainActor @ViewBuilder
    private func actionRow(text: String, sourceID: String) -> some View {
        HStack(spacing: 0) {
            Button {
                copyToClipboard(text)
            } label: {
                Image(systemName: "doc.on.doc").font(.caption)
            }
            .foregroundStyle(.secondary)
            .help("Copy message")

            if let onRegenerate {
                Button {
                    onRegenerate(sourceID)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .foregroundStyle(.secondary)
                .help("Regenerate response")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.text(size: .small, square: true))
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }
}

/// Wraps `AssistantRoundView` with stream observation. The in-flight assistant
/// message is synthesized from `stream` and appended to `committedMessages`
/// before splitting into intermediate / final. All text smoothing is delegated
/// to `SmoothStreamingText` — no separate text buffer here.
private struct LiveAssistantRoundView: View {
    let committedMessages: [ChatMessage]
    @ObservedObject var stream: LLMStreamingStateObject
    var onRegenerate: ((String) -> Void)?
    var onStreamUpdate: (() -> Void)?

    private var inflightMessage: ChatMessage {
        let toolCalls = stream.toolCalls.isEmpty ? nil : stream.toolCalls
        return .content(.init(
            id: stream.id,
            role: .assistant,
            content: stream.content,
            files: stream.files,
            usage: nil,
            toolCalls: toolCalls
        ))
    }

    var body: some View {
        AssistantRoundView(
            messages: committedMessages + [inflightMessage],
            inflightID: stream.id,
            isActive: !stream.isFinished,
            onRegenerate: onRegenerate
        )
        .onChange(of: stream.content) { _ in
            onStreamUpdate?()
        }
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
