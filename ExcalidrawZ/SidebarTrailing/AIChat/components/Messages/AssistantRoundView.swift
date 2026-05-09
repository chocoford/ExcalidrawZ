//
//  AssistantRoundView.swift
//  ExcalidrawZ
//
//  Self-contained per-round reveal. From this view's perspective each
//  displayable message is in one of two macro-states:
//
//   - "currently streaming" — the LLM is still emitting bytes for it.
//     Identified by `msg.id == streamingID && !streamFinished`. The
//     row is laid out at full height (so the scroll view sees its
//     final size) but `chatTopDownReveal(progress: 0)` masks it
//     invisible. Content updates from the model don't visually flicker
//     because the mask is fully closed.
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
//  pulls `streamingID` / `streamFinished` from props and the smooth-
//  scroll callback from `@Environment(\.chatScrollToBottom)`.
//

import SwiftUI
import LLMCore
import LLMKit
import ChocofordUI
#if canImport(AppKit)
import AppKit
#endif

struct AssistantRoundView: View {
    @EnvironmentObject private var aiChatState: AIChatState
    @Environment(\.chatScrollToBottom) private var chatScrollToBottom

    let roundID: String
    let messages: [ChatMessage]
    /// The id LLMKit is currently streaming. May or may not belong to
    /// this round.
    let streamingID: String?
    /// True when the in-flight stream has reported `isFinished`. Once
    /// this flips, the message whose id equals `streamingID` is
    /// considered complete (LLMKit doesn't always rotate the id at
    /// stream end).
    let streamFinished: Bool
    /// Id of the round currently being driven by the in-flight stream
    /// (`nil` when no stream is active). When `roundID == activeRoundID`
    /// this round is the one being generated — `init` starts with an
    /// empty `revealedIDs` so every message goes through the reveal
    /// pipeline. Otherwise the round is historical / settled and all
    /// messages render fully from frame 1.
    ///
    /// We can't derive this from `streamingID` alone: LLMKit can commit
    /// several messages per round in quick succession (e.g. "Let me
    /// observe…" → toolCall msg). Between commits SwiftUI coalesces
    /// renders, so by the time the round first mounts several messages
    /// may already exist with `streamingID` pointing PAST them (at the
    /// next, not-yet-committed message). A per-id "is this the streaming
    /// target" check then misses every already-committed message and
    /// pre-marks them revealed — which is the bug where the next
    /// message's tool card showed up unanimated.
    let activeRoundID: String?
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
    private static let layoutFlushDelay: Duration = .milliseconds(80)
    private static let actionBarDelay: Duration = .seconds(1)

    init(
        roundID: String,
        messages: [ChatMessage],
        streamingID: String?,
        streamFinished: Bool,
        activeRoundID: String?,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.roundID = roundID
        self.messages = messages
        self.streamingID = streamingID
        self.streamFinished = streamFinished
        self.activeRoundID = activeRoundID
        self.onRegenerate = onRegenerate

        // The round-level "is this round being streamed" gate (not a
        // per-message one). For an active round, every displayable
        // message goes through the queue — even ones that were already
        // committed by the time this view first mounted. For a settled
        // / historical round, every displayable message is pre-marked
        // revealed.
        let displayableIDs = Self.displayableMessageIDs(in: messages)
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
        VStack(alignment: .leading, spacing: 10) {
            messagesContent

            if showsLoadingRow {
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
            if let target = lastAssistantMessage,
               case .content(let c) = target,
               displayText(of: c).nonEmpty != nil {
                actionRow(
                    copyText: aggregatedAssistantText,
                    sourceID: c.id
                )
                .opacity(showsActionBar ? 1 : 0)
                .allowsHitTesting(showsActionBar)
                .padding(.bottom, 40)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsActionBar)
        .animation(.easeOut(duration: 0.25), value: showsLoadingRow)
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
            ForEach(displayableMessages) { msg in
                messageRow(msg)
                    .chatTopDownReveal(progress: progress(for: msg.id))
            }
        }
    }

    private func progress(for id: String) -> CGFloat {
        revealedIDs.contains(id) ? 1 : 0
    }

    @MainActor @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        if case .content(let c) = msg {
            switch c.role {
                case .tool:
                    ToolResultCard(content: c)
                case .assistant:
                    assistantMessage(c)
                default:
                    EmptyView()
            }
        }
    }

    @MainActor @ViewBuilder
    private func assistantMessage(_ c: ChatMessageContent) -> some View {
        let text = displayText(of: c)
        let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
        if !text.isEmpty || !nonFinalCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !text.isEmpty {
                    SmoothStreamingText(target: text, isStreaming: false)
                        .padding(.bottom, 6)
                }
                ForEach(nonFinalCalls, id: \.id) { call in
                    ToolCallCard(
                        call: call,
                        isActive: false,
                        isDenied: isCallDenied(call)
                    )
                }
            }
        }
    }

    // MARK: - Completion driver

    /// Hashable snapshot of every input that affects the
    /// completeness decision. `.task(id:)` re-runs
    /// `handleCompletionChange` whenever this changes — when a new
    /// message commits, when the streaming id rotates, when the
    /// stream ends, OR when an in-flight assistant message's
    /// `toolCalls` flips from empty → non-empty (the LLM stream's
    /// tail signal).
    private var completionSignature: String {
        let ids = messages.compactMap { msg -> String? in
            switch msg {
                case .content(let c):
                    // Include a 0/1 marker for whether toolCalls is
                    // populated. The transition empty → non-empty is
                    // the signal we use to mark an assistant message
                    // "stream done" while `streamingID` is still
                    // pinned on it.
                    let toolMarker = (c.toolCalls?.isEmpty ?? true) ? "0" : "1"
                    return "\(c.id):\(toolMarker)"
                case .loading(let id): return "loading:\(id.uuidString)"
                case .error(let id, _): return "error:\(id.uuidString)"
            }
        }.joined(separator: ",")
        return "\(streamingID ?? "nil")::\(streamFinished)::\(ids)"
    }

    /// True iff a message's LLM stream has reached a stable end-state
    /// — its content + toolCalls aren't going to change.
    ///
    /// LLMKit's `streamingID` represents "current LLM stream target"
    /// at the **agent-run** level, not per-message. Between rounds
    /// (during tool execution by AgentExecutor) it stays pinned on
    /// the previous assistant message even though that message's
    /// stream has long since finished. Relying on
    /// `id == streamingID` alone holds the message hidden through
    /// tool execution, which can be slow (e.g. `adjust_element`).
    ///
    /// Instead we lean on the LLM's own end-of-message signal:
    /// `toolCalls` arrive at the tail of the stream, so a
    /// streaming-target message that already has any toolCalls is
    /// effectively complete. The corner case — a pure-text message
    /// with no toolCalls — only happens for the agent's terminal
    /// answer, by which time `streamFinished` flips true.
    private static func isStreamDone(
        _ msg: ChatMessage,
        streamingID: String?,
        streamFinished: Bool
    ) -> Bool {
        guard case .content(let c) = msg else { return true }
        // `role: .tool` messages are synthesized synchronously by
        // AgentExecutor after each tool returns — they're stable
        // the moment they appear in the array.
        if c.role == .tool { return true }
        // Whole agent run is done.
        if streamFinished { return true }
        // Not the current streaming target → previous round's, done.
        if c.id != streamingID { return true }
        // Streaming target with toolCalls populated → tail of stream,
        // content has already been emitted, the message is stable.
        if !((c.toolCalls ?? []).isEmpty) { return true }
        // Streaming target, no toolCalls yet → still streaming.
        return false
    }

    /// Any message still in flight (LLM stream not yet at tail)?
    /// Drives the loading row.
    private var hasInflightInRound: Bool {
        guard !streamFinished else { return false }
        return messages.contains { msg in
            !Self.isStreamDone(msg, streamingID: streamingID, streamFinished: streamFinished)
        }
    }

    /// Loading row: shown only while a message in this round is still
    /// mid-stream AND no reveal has landed yet. Once the first reveal
    /// lands, the row's content takes over.
    private var showsLoadingRow: Bool {
        guard hasInflightInRound else { return false }
        return revealedIDs.isEmpty
    }

    @MainActor
    private func handleCompletionChange() {
        let queueSet = Set(revealQueue)
        var toEnqueue: [String] = []
        // Iterate in commit order. We BREAK (not `continue`) the
        // moment we hit a message whose stream isn't done yet —
        // anything past it is positionally later and must wait its
        // turn. AgentExecutor synchronously injects tool-result
        // messages while the preceding assistant message's
        // `streamingID` may still be pinned, so without the break a
        // tool result could get enqueued before the assistant
        // message + its inline toolCallCard.
        for msg in displayableMessages {
            guard case .content(let c) = msg else { continue }
            let id = c.id
            if revealedIDs.contains(id) { continue }
            if queueSet.contains(id) { continue }
            if !Self.isStreamDone(
                msg,
                streamingID: streamingID,
                streamFinished: streamFinished
            ) {
                break
            }
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

    /// Schedule the action row's appearance once the round is fully
    /// done. "Done" requires `streamFinished` — the whole agent run
    /// has signed off — not just "no message currently mid-stream".
    /// The latter would fire prematurely during the tool-execution
    /// gaps between LLM rounds (M.1 done, M.2 not yet injected,
    /// `streamingID` still pinned on M.1, `hasInflightInRound`
    /// transiently false).
    ///
    /// Once flipped true, we never flip back to false. A historical
    /// round mounts with `showsActionBar = true` at init; signature
    /// changes from new conversations / streams should never tear it
    /// down.
    private func evaluateActionBar() {
        let allRevealed = displayableMessages.allSatisfy { msg in
            guard case .content(let c) = msg else { return true }
            return revealedIDs.contains(c.id)
        }
        let settled = streamFinished && allRevealed
        actionBarTask?.cancel()
        actionBarTask = nil
        guard settled, !showsActionBar else { return }
        actionBarTask = Task { @MainActor [self] in
            try? await Task.sleep(for: Self.actionBarDelay)
            guard !Task.isCancelled else { return }
            showsActionBar = true
        }
    }

    // MARK: - Helpers

    private var displayableMessages: [ChatMessage] {
        messages.filter(Self.isDisplayable)
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

    private static func displayableMessageIDs(in messages: [ChatMessage]) -> [String] {
        messages.compactMap { msg -> String? in
            guard isDisplayable(msg), case .content(let c) = msg else {
                return nil
            }
            return c.id
        }
    }

    private func isCallDenied(_ call: ToolCall) -> Bool {
        messages.contains { msg in
            guard case .content(let c) = msg,
                  c.role == .tool,
                  c.toolCallId == call.id else { return false }
            return c.content?.hasPrefix("User denied execution of") == true
        }
    }

    private var aggregatedAssistantText: String {
        messages
            .compactMap { msg -> String? in
                guard case .content(let c) = msg, c.role == .assistant else {
                    return nil
                }
                let text = displayText(of: c)
                return text.isEmpty ? nil : text
            }
            .joined(separator: "\n\n")
    }

    private func displayText(of c: ChatMessageContent) -> String {
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return c.content ?? ""
    }

    private var lastAssistantMessage: ChatMessage? {
        messages.last(where: { msg in
            guard case .content(let c) = msg else { return false }
            return c.role == .assistant
        })
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
