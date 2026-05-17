//
//  AssistantRoundView.swift
//  ExcalidrawZ
//
//  Self-contained per-round reveal. From this view's perspective each
//  displayable message is in one of two macro-states:
//
//   - "currently streaming" — the LLM is still emitting bytes for a
//     committed partial assistant message. Identified by
//     `llmState.isStreaming(messageID:in:)` in the parent and passed
//     here as `streamingMessageIDs`. The row is laid out at full height
//     (so the scroll view sees its final size) but
//     `chatTopDownReveal(progress: 0)` masks it invisible. Content
//     updates from the model don't visually flicker because the mask is
//     fully closed.
//   - "complete" — the LLM has moved on to a different message id, or
//     the stream has finished. Eligible for reveal.
//
//  A complete message that hasn't been revealed yet enters a per-round
//  serial queue: place (already laid out) → wait for layout flush →
//  await smooth scroll-to-bottom → `withAnimation` set
//  `revealedIDs.insert(id)` (drives `chatTopDownReveal` `0 → 1`).
//
//  At init, every displayable message that is NOT currently streaming
//  is pre-marked as revealed — historical content (chat reopened,
//  conversation switched into) renders instantly with no fade-in.
//
//  No external controller, no priming, no `expectedRoundIDs`. The view
//  pulls per-message streaming ids from props and the smooth-scroll
//  callback from `@Environment(\.chatScrollToBottom)`.
//

import SwiftUI
import LLMCore
import LLMKit
import ChocofordUI
#if canImport(AppKit)
import AppKit
#endif

struct AssistantRoundView: View {
    @Environment(\.chatScrollToBottom) private var chatScrollToBottom

    let roundID: String
    let messages: [ChatMessage]
    /// Committed assistant message ids that LLMKit still considers
    /// actively streaming.
    let streamingMessageIDs: Set<String>
    let isRoundCancelled: Bool
    /// Id of the round currently being driven by the in-flight stream
    /// (`nil` when no stream is active). When `roundID == activeRoundID`
    /// this round is the one being generated — `init` starts with an
    /// empty `revealedIDs` so every message goes through the reveal
    /// pipeline. Otherwise the round is historical / settled and all
    /// messages render fully from frame 1.
    ///
    /// We can't derive this from per-message streaming alone: LLMKit can commit
    /// several messages per round in quick succession (e.g. "Let me
    /// observe…" → toolCall msg). Between commits SwiftUI coalesces
    /// renders, so by the time the round first mounts several messages
    /// may already exist and no longer be streaming. A per-id streaming
    /// check alone would pre-mark them revealed — which is the bug where
    /// the next message's tool card showed up unanimated.
    let activeRoundID: String?
    let usesExternalLoadingSlot: Bool
    let onRegenerate: ((String) -> Void)?

    /// Messages whose `chatTopDownReveal` should render at progress 1.
    /// At init this contains every displayable message that wasn't the
    /// active streaming target — historical content shows immediately.
    /// Mid-life, the queue inserts ids here under `withAnimation`,
    /// which drives the wipe.
    @State private var revealedIDs: Set<String>
    /// FIFO of ids that are complete but haven't yet been revealed.
    /// Appended from `.task(id: completionSignature)`, drained by
    /// `queueTask`.
    @State private var revealQueue: [String]
    @State private var queueTask: Task<Void, Never>?
    /// True when the action row should be visible. Init from the static
    /// "all-revealed" check; mid-life, the post-reveal 1 s timer
    /// flips it.
    @State private var showsActionBar: Bool
    @State private var actionBarTask: Task<Void, Never>?

    private static let revealDuration: Double = 0.3
    private static let layoutFlushDelay: Duration = .milliseconds(200)
    private static let actionBarDelay: Duration = .seconds(1)

    private enum RenderItem: Identifiable {
        case assistantContent(ChatMessageContent)
        case assistantToolCall(messageID: String, call: ToolCall)
        case toolResult(ChatMessageContent)

        var id: String {
            switch self {
                case .assistantContent(let content):
                    return "\(content.id):content"
                case .assistantToolCall(let messageID, let call):
                    return "\(messageID):toolCall:\(call.id)"
                case .toolResult(let content):
                    return "\(content.id):toolResult"
            }
        }
    }

    init(
        roundID: String,
        messages: [ChatMessage],
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isRoundCancelled: Bool = false,
        usesExternalLoadingSlot: Bool = false,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.roundID = roundID
        self.messages = messages
        self.activeRoundID = activeRoundID
        self.streamingMessageIDs = streamingMessageIDs
        self.isRoundCancelled = isRoundCancelled
        self.usesExternalLoadingSlot = usesExternalLoadingSlot
        self.onRegenerate = onRegenerate

        // The round-level "is this round being streamed" gate (not a
        // per-message one). For an active round, every displayable
        // message goes through the queue — even ones that were already
        // committed by the time this view first mounted. For a settled
        // / historical round, every displayable message is pre-marked
        // revealed.
        let displayableIDs = Self.renderItems(
            in: messages,
            streamingMessageIDs: streamingMessageIDs
        ).map(\.id)
        let isActiveRound = (roundID == activeRoundID)
        let initialRevealed: [String] = isActiveRound ? [] : displayableIDs
        self._revealedIDs = State(initialValue: Set(initialRevealed))
        self._revealQueue = State(initialValue: [])

        // Action row visible immediately on a historical mount; for
        // an active mount, it stays hidden until the reveal pipeline
        // drains and the 1 s grace timer fires.
        self._showsActionBar = State(initialValue: !isActiveRound)
    }

    var body: some View {
        let _ = AIChatRenderDebug.hit("AssistantRoundView.body")

        VStack(alignment: .leading, spacing: 10) {
            messagesContent

            if !usesExternalLoadingSlot, showsLoadingRow {
                LoadingMessageRow()
                    .transition(.opacity)
            }

            // Render the action row once the round has any final-
            // answer-bearing assistant message. Visibility is then
            // controlled by `showsActionBar` via opacity, so the row's
            // height is reserved up-front and the eventual reveal
            // doesn't shift the messages above. Without this, the
            // last message would jump when the action row materializes
            // a second after settling.
            if let target = lastActionableAssistantContent,
               displayText(of: target).nonEmpty != nil {
                actionRow(
                    copyText: aggregatedLaidOutAssistantText,
                    sourceID: target.id
                )
                .opacity(showsActionBar ? 1 : 0)
                .allowsHitTesting(showsActionBar)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsActionBar)
        .animation(.easeOut(duration: 0.2), value: showsLoadingRow)
        .task(id: completionSignature) {
            handleCompletionChange()
        }
        .onDisappear {
            queueTask?.cancel()
            actionBarTask?.cancel()
        }
    }

    // MARK: - Rendering

    @ViewBuilder
    private var messagesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(renderItems) { item in
                renderItem(item)
                    .chatTopDownRevealFrame(progress: progress(for: item.id))
            }
        }
    }

    private func progress(for id: String) -> CGFloat {
        revealedIDs.contains(id) ? 1 : 0
    }

    @MainActor @ViewBuilder
    private func renderItem(_ item: RenderItem) -> some View {
        switch item {
            case .assistantContent(let content):
                assistantContent(content)
            case .assistantToolCall:
                assistantToolCall(item)
            case .toolResult(let content):
                ToolResultCard(content: content)
        }
    }

    @MainActor @ViewBuilder
    private func assistantContent(_ c: ChatMessageContent) -> some View {
        let text = displayText(of: c)
        if !text.isEmpty {
            SmoothStreamingText(
                target: text,
                isStreaming: streamingMessageIDs.contains(c.id)
            )
                .padding(.bottom, 6)
                .assistantContentStableHeight(
                    cacheKey: "assistantContent:\(c.id):c\(text.count):text:\(text.hashValue):streaming:\(streamingMessageIDs.contains(c.id) ? "1" : "0")",
                    isStreaming: streamingMessageIDs.contains(c.id)
                )
        }
    }

    @MainActor @ViewBuilder
    private func assistantToolCall(_ item: RenderItem) -> some View {
        if case .assistantToolCall(let messageID, let call) = item {
            ToolCallCard(
                call: call,
                isActive: streamingMessageIDs.contains(messageID),
                isDenied: isCallDenied(call)
            )
        }
    }

    // MARK: - Completion driver

    /// Hashable snapshot of every input that affects the
    /// completeness decision. `.task(id:)` re-runs
    /// `handleCompletionChange` whenever this changes — when a new
    /// message commits or when LLMKit's per-message streaming status
    /// flips false.
    private var completionSignature: String {
        let ids = messages.compactMap { msg -> String? in
            switch msg {
                case .content(let c):
                    let streamingMarker = streamingMessageIDs.contains(c.id) ? "1" : "0"
                    let toolCallMarker = c.toolCalls.map { calls in
                        calls.map { call in
                            Self.toolCallSignature(
                                call,
                                content: c,
                                streamingMessageIDs: streamingMessageIDs
                            )
                        }.joined(separator: ",")
                    } ?? "nil"
                    return "\(c.id):\(streamingMarker):\(Self.contentSignature(c, streamingMessageIDs: streamingMessageIDs)):tc[\(toolCallMarker)]"
                case .loading(let id):
                    return "loading:\(id.uuidString)"
                case .error(let id, _):
                    return "error:\(id.uuidString)"
            }
        }.joined(separator: ",")
        return "\(activeRoundID ?? "nil")::cancel:\(isRoundCancelled ? "1" : "0")::\(ids)"
    }

    private static func contentSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard content.role == .assistant,
              streamingMessageIDs.contains(content.id),
              shouldHideStreamingAssistantContent(content)
        else {
            return "c\(content.content?.count ?? 0)"
        }
        return "hidden-streaming-content"
    }

    private static func toolCallSignature(
        _ call: ToolCall,
        content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        let isHiddenStreamingAssistant = content.role == .assistant
            && streamingMessageIDs.contains(content.id)
        if isHiddenStreamingAssistant {
            return "\(call.id):\(call.name):hidden-streaming-args"
        }
        return "\(call.id):\(call.name):a\(call.arguments.count)"
    }

    private static func shouldHideStreamingAssistantContent(_ content: ChatMessageContent) -> Bool {
        let hasFinalCall = content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
        if hasFinalCall { return true }
        let text = displayText(of: content)
        guard !text.isEmpty else { return false }
        let hasToolCallsStarted = content.toolCalls != nil
        return !hasToolCallsStarted
    }

    /// True iff a message's LLM stream has reached a stable end-state
    /// — LLMKit is no longer streaming into its committed id.
    private static func isStreamDone(
        _ msg: ChatMessage,
        streamingMessageIDs: Set<String>
    ) -> Bool {
        guard case .content(let c) = msg else { return true }
        // `role: .tool` messages are synthesized synchronously by
        // AgentExecutor after each tool returns — they're stable
        // the moment they appear in the array.
        if c.role == .tool { return true }
        return !streamingMessageIDs.contains(c.id)
    }

    @MainActor
    private func handleCompletionChange() {
        let queueSet = Set(revealQueue)
        var toEnqueue: [String] = []
        for item in renderItems {
            let id = item.id
            if revealedIDs.contains(id) { continue }
            if queueSet.contains(id) { continue }
            toEnqueue.append(id)
        }
        if !toEnqueue.isEmpty {
            revealQueue.append(contentsOf: toEnqueue)
            startQueueIfNeeded()
        }
        // Even if nothing was newly enqueued, re-evaluate the action
        // bar: streaming may have just finished on an already-revealed
        // last message.
        evaluateActionBar()
    }

    /// Any assistant message in this round whose LLM stream has not
    /// reached the tail yet. Stable render items can reveal before this
    /// flips false; the row remains visible while the rest of that
    /// message is still arriving.
    private var hasInflightInRound: Bool {
        return messages.contains { msg in
            !Self.isStreamDone(msg, streamingMessageIDs: streamingMessageIDs)
        }
    }

    /// Show while the current hidden message is actively streaming.
    /// As soon as the message becomes stable, this disappears before
    /// the reveal queue performs its place -> scroll -> wipe-in sequence.
    private var showsLoadingRow: Bool {
        hasInflightInRound
    }

    private func startQueueIfNeeded() {
        guard queueTask == nil else { return }
        queueTask = Task { @MainActor [self] in
            await drain()
            queueTask = nil
        }
    }

    private func drain() async {
        while !revealQueue.isEmpty {
            let id = revealQueue.removeFirst()
            // Layout flush: SwiftUI needs a beat to push the
            // `chatTopDownReveal(progress: 0)` row's height into the
            // hosting view before scroll-to-bottom can target the new
            // bottom. `Task.yield` alone isn't enough — need actual
            // wall-clock time for the AppKit/UIKit layout pass.
            try? await Task.sleep(for: Self.layoutFlushDelay)
            // Smooth scroll, await its completion. If the env hook
            // isn't installed (preview, test), this no-ops and we
            // still proceed.
            await chatScrollToBottom?(true)
            // Wipe in. The Animatable on `ChatTopDownRevealModifier`
            // interpolates `progress` 0 → 1 because the change
            // happens inside `withAnimation`.
            withAnimation(.easeOut(duration: Self.revealDuration)) {
                _ = revealedIDs.insert(id)
            }
            try? await Task.sleep(for: .seconds(Self.revealDuration))
        }
        evaluateActionBar()
    }

    /// Schedule the action row's appearance once this round is no longer
    /// the active generating round and every displayable row has revealed.
    /// Per-message streaming alone is not enough: it can flip false
    /// between tool/assistant phases while the agent turn is still
    /// producing more rows for the same active round.
    ///
    /// Once flipped true, we never flip back to false. A historical
    /// round mounts with `showsActionBar = true` at init; signature
    /// changes from new conversations / streams should never tear it
    /// down.
    private func evaluateActionBar() {
        let allRevealed = renderItems.allSatisfy { revealedIDs.contains($0.id) }
        let isActiveGeneratingRound = (roundID == activeRoundID)
        let settled = !isActiveGeneratingRound
            && !hasInflightInRound
            && allRevealed
            && hasTerminalActionableAssistantContent
        guard settled else {
            actionBarTask?.cancel()
            actionBarTask = nil
            return
        }
        guard !showsActionBar, actionBarTask == nil else { return }
        actionBarTask = Task { @MainActor [self] in
            try? await Task.sleep(for: Self.actionBarDelay)
            guard !Task.isCancelled else { return }
            showsActionBar = true
            actionBarTask = nil
        }
    }

    // MARK: - Helpers

    private var displayableMessages: [ChatMessage] {
        messages.filter(Self.isDisplayable)
    }

    /// Rows that are allowed to participate in layout. Assistant
    /// content can become stable before its tool-calls finish; tool
    /// call cards wait until the whole assistant message is stable.
    private var renderItems: [RenderItem] {
        Self.renderItems(in: messages, streamingMessageIDs: streamingMessageIDs)
    }

    private static func renderItems(
        in messages: [ChatMessage],
        streamingMessageIDs: Set<String>
    ) -> [RenderItem] {
        var result: [RenderItem] = []
        for message in messages {
            guard isDisplayable(message), case .content(let content) = message else {
                continue
            }
            switch content.role {
                case .tool:
                    result.append(.toolResult(content))
                case .assistant:
                    let isStreaming = streamingMessageIDs.contains(content.id)
                    let text = displayText(of: content)
                    let hasFinalCall = hasFinalAnswerToolCall(in: content)
                    let hasToolCallsStarted = content.toolCalls != nil
                    let contentIsStable = !isStreaming
                        || (!hasFinalCall && hasToolCallsStarted && !text.isEmpty)

                    if !text.isEmpty {
                        guard contentIsStable else { return result }
                        result.append(.assistantContent(content))
                    }

                    let nonFinalCalls = nonFinalToolCalls(in: content)
                    if !nonFinalCalls.isEmpty {
                        result.append(
                            contentsOf: nonFinalCalls.map {
                                .assistantToolCall(messageID: content.id, call: $0)
                            }
                        )
                    } else if isStreaming {
                        return result
                    }
                default:
                    continue
            }
        }
        return result
    }

    private static func isDisplayable(_ msg: ChatMessage) -> Bool {
        guard case .content(let c) = msg else { return false }
        let text: String = {
            if let final = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
                return parseFinalAnswerArgs(final.arguments)
            }
            return c.content ?? ""
        }()
        return !text.isEmpty || !((c.toolCalls ?? []).isEmpty)
    }

    private func isCallDenied(_ call: ToolCall) -> Bool {
        messages.contains { msg in
            guard case .content(let c) = msg,
                  c.role == .tool,
                  c.toolCallId == call.id else { return false }
            return c.content?.hasPrefix("User denied execution of") == true
        }
    }

    private var aggregatedLaidOutAssistantText: String {
        renderItems
            .compactMap { msg -> String? in
                guard case .assistantContent(let content) = msg else {
                    return nil
                }
                let text = displayText(of: content)
                return text.isEmpty ? nil : text
            }
            .joined(separator: "\n\n")
    }

    private static func displayText(of c: ChatMessageContent) -> String {
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return c.content ?? ""
    }

    private func displayText(of c: ChatMessageContent) -> String {
        Self.displayText(of: c)
    }

    private var lastActionableAssistantContent: ChatMessageContent? {
        guard case .assistantContent(let content) = renderItems.last(where: { item in
            guard case .assistantContent(let content) = item else { return false }
            return !Self.displayText(of: content).isEmpty
        }) else {
            return nil
        }
        return content
    }

    private var hasTerminalActionableAssistantContent: Bool {
        guard let content = lastActionableAssistantContent else { return false }
        if isRoundCancelled { return true }
        if Self.hasFinalAnswerToolCall(in: content) { return true }
        return Self.nonFinalToolCalls(in: content).isEmpty
    }

    private static func nonFinalToolCalls(in content: ChatMessageContent) -> [ToolCall] {
        (content.toolCalls ?? []).filter { $0.name != "final_answer" }
    }

    private static func hasFinalAnswerToolCall(in content: ChatMessageContent) -> Bool {
        content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
    }

    // MARK: - Action row

    @MainActor @ViewBuilder
    private func actionRow(copyText: String, sourceID: String) -> some View {
        HStack(spacing: 0) {
            CopyButton(text: copyText)
            if let onRegenerate {
                Button {
                    onRegenerate(sourceID)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .foregroundStyle(.secondary)
                .help("Regenerate response")
            }
            Spacer()
            let usage = messages.reduce(0) { $0 + ($1.usage?.consumed ?? 0) }
            HStack(spacing: 4) {
                Image(systemSymbol: .boltCircle)
                Text(usage.formatted(.number.precision(.fractionLength(2))))
            }
            .font(.footnote)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(.regularMaterial)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.text(size: .normal, square: true))
    }
}

extension AssistantRoundView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.roundID == rhs.roundID
            && lhs.messages == rhs.messages
            && lhs.streamingMessageIDs == rhs.streamingMessageIDs
            && lhs.isRoundCancelled == rhs.isRoundCancelled
            && lhs.activeRoundID == rhs.activeRoundID
            && lhs.usesExternalLoadingSlot == rhs.usesExternalLoadingSlot
    }
}

// MARK: - Environment key for the smooth-scroll callback

private struct ChatScrollToBottomKey: EnvironmentKey {
    static let defaultValue: ((Bool) async -> Void)? = nil
}

extension EnvironmentValues {
    /// Async smooth scroll-to-bottom installed by `AIChatView`.
    /// `AssistantRoundView` awaits this between "place" and "wipe in"
    /// so the reveal animation runs at the new viewport bottom.
    var chatScrollToBottom: ((Bool) async -> Void)? {
        get { self[ChatScrollToBottomKey.self] }
        set { self[ChatScrollToBottomKey.self] = newValue }
    }
}

// MARK: - Copy button

/// Copy button with an inline "copied" confirmation.
struct CopyButton: View {
    let text: String
    @State private var copied: Bool = false
    @State private var revertTask: Task<Void, Never>?

    private static let revertDelay: Duration = .seconds(1.4)

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = true
            }
            revertTask?.cancel()
            revertTask = Task { @MainActor in
                try? await Task.sleep(for: Self.revertDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    copied = false
                }
            }
        } label: {
            ZStack {
                if #available(macOS 15.0, *) {
                    Image(systemSymbol: copied ? .checkmark : .documentOnDocument)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemSymbol: copied ? .checkmark : .docOnDoc)
                }
            }
            .frame(width: 14, height: 14)
            .font(.caption)
        }
        .foregroundStyle(copied ? Color.green : .secondary)
        .help("Copy message")
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
