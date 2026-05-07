//
//  AssistantRoundView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  One full agent turn rendered Xcode-style: flat, no AI-side bubble. **Every**
//  assistant message renders via the same `SmoothStreamingText` chain, in its
//  natural position in the round's message list. There used to be a "final
//  answer / intermediate step" split that put the latest answer in a separate
//  bottom slot; that caused the SmoothStreamingText to remount whenever a
//  message moved between slots (typically when a new round started), which
//  killed `@StateObject` flusher state and short-circuited the reveal animation.
//
//  Unified rendering: each message keeps a stable position keyed by its id.
//  `inflightID` tells which one is still streaming (drives `isStreaming` on
//  that one's `SmoothStreamingText`); the rest render committed.
//
//  `LiveAssistantRoundView` is the streaming wrapper: it observes the in-flight
//  stream object and synthesizes the inflight assistant message into the
//  round's message list before delegating render to `AssistantRoundView`.
//

import SwiftUI
import Combine
import LLMCore
import LLMKit
import ChocofordUI
#if canImport(AppKit)
import AppKit
#endif

struct AssistantRoundView: View {
    /// App-level chat state — used to publish tool-call reveals out so
    /// `ApprovalPromptView` knows when the corresponding card is on
    /// screen and can stop holding back its prompt.
    @EnvironmentObject private var aiChatState: AIChatState

    let messages: [ChatMessage]
    /// Which message inside this round is currently streaming, if any.
    /// The matching message renders with `isStreaming=true`; others render
    /// committed. Also gates the action row (no copy/regenerate while live).
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

    /// Action row reveal is delayed until the masking animation inside
    /// `SmoothStreamingText` (catch-up + fade strip shrink, ~0.5 s) has had
    /// time to settle. Slightly longer than the 0.5 s `.smooth(duration:)` so
    /// we don't overlap the tail of the spring's settling.
    private static let actionRevealDelay: Duration = .milliseconds(600)

    @State private var actionsVisible: Bool = false
    /// Tracks whether `.task(id:)` has run at least once. The first run sets
    /// the initial visibility synchronously (no delay) so committed-history
    /// rounds — which mount with the round already finished — show actions
    /// immediately rather than after a needless 600 ms wait.
    @State private var actionsTimingBootstrapped: Bool = false

    /// Sequential reveal of content / tool calls / tool results within
    /// the round. Live rounds (`isActive`) walk the queue with dwell +
    /// readiness gates; committed history snaps everything on first
    /// mount. See `RoundRevealOrchestrator` for the state machine.
    @StateObject private var revealer = RoundRevealOrchestrator()
    /// First-mount sentinel — decides snap vs paced. After bootstrap,
    /// subsequent body re-evals always go through `update(_:)` even if
    /// `isActive` flips false (queue continues to drain naturally).
    @State private var revealerBootstrapped: Bool = false

    var body: some View {
        let actionTarget = actionRowTarget
        let isLiveTrailing = isActive && lastAssistantMessage?.id == inflightID
        let revealElements = computeRevealElements()

        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { msg in
                messageRow(msg)
            }

            if isActive && hasAnyMessageWithSubstance && !hasAnyVisibleContent {
                LoadingMessageRow()
                    .transition(.opacity)
            }

            if let target = lastAssistantMessage,
               case .content(let c) = target,
               displayText(of: c).nonEmpty != nil {
                // Copy aggregates across the whole round (every assistant
                // message's text joined by blank lines), not just the
                // trailing message — so a multi-step turn copies all the
                // reasoning + final answer in order. Regenerate is still
                // anchored to the trailing message because LLMKit's
                // `regenerate(fromMessageID:)` walks back from there.
                actionRow(
                    copyText: aggregatedAssistantText,
                    sourceID: c.id
                )
                .opacity(actionsVisible ? 1 : 0)
                .allowsHitTesting(actionsVisible)
                .animation(.easeInOut(duration: 0.3), value: actionsVisible)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .border(.red)
        // Per-element reveal animation — drives the fade-ins of
        // `SmoothStreamingText` / `ToolCallCard` / `ToolResultCard` as
        // the orchestrator advances `revealedIDs`. Separate from
        // `structureSig` so a tool-call appearing within an existing
        // assistant message doesn't trigger the round-level slide.
        .animation(.easeOut(duration: 0.25), value: revealer.revealedIDs)
        .onChange(of: revealElements) { newElements in
            guard revealerBootstrapped else { return }
            revealer.update(newElements)
        }
        // Push tool-call reveals out to `aiChatState` so the approval
        // prompt knows when its target card is actually visible.
        // Element-id format is `"toolcall:<msgID>:<callID>"`; we want
        // just the trailing call id since LLMKit's
        // `ToolApprovalRequest.toolCallID` is the bare call id.
        .onChange(of: revealer.revealedIDs) { newIDs in
            for id in newIDs {
                if id.hasPrefix("toolcall:") {
                    let parts = id.split(separator: ":")
                    if let callID = parts.last, parts.count >= 3 {
                        aiChatState.markToolCallRevealed(String(callID))
                    }
                }
            }
        }
        .task(id: isLiveTrailing) {
            await scheduleActionsVisibility(isLiveTrailing: isLiveTrailing)
        }
        .onAppear {
            // First mount: pace if active (live round), snap otherwise
            // (committed history). After this, only `onChange` updates
            // run — `isActive` flipping false mid-stream just means the
            // queue keeps draining naturally, no re-bootstrap.
            if !revealerBootstrapped {
                revealerBootstrapped = true
                if isActive {
                    revealer.update(revealElements)
                } else {
                    revealer.revealAllImmediately(revealElements)
                }
            }
        }

    }

    // MARK: - Reveal elements

    /// Flatten the round into the orchestrator's element list.
    /// Order matters — it's the visual order of reveal.
    private func computeRevealElements() -> [RoundRevealOrchestrator.Element] {
        var result: [RoundRevealOrchestrator.Element] = []
        for msg in messages {
            guard case .content(let c) = msg else { continue }
            switch c.role {
                case .assistant:
                    let text = displayText(of: c)
                    let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
                    let isInflight = (msg.id == inflightID && isActive)
                    let hasToolCalls = !nonFinalCalls.isEmpty

                    if !text.isEmpty || isInflight {
                        // Content is "ready" (next element can advance) when:
                        // - it's a committed message (not in-flight), OR
                        // - tool calls have arrived in this same message
                        //   (model sealed the content and switched to tool
                        //   use), OR
                        // - this message is no longer the inflight one.
                        // The remaining case — in-flight, no tool calls
                        // yet — is precisely "content still streaming",
                        // which holds the gate closed.
                        let isReady = !isInflight || hasToolCalls
                        result.append(.init(
                            id: "content:\(c.id)",
                            kind: .content,
                            isReady: isReady
                        ))
                    }
                    for call in nonFinalCalls {
                        result.append(.init(
                            id: "toolcall:\(c.id):\(call.id)",
                            kind: .toolCall,
                            isReady: true
                        ))
                    }
                case .tool:
                    result.append(.init(
                        id: "toolresult:\(c.id)",
                        kind: .toolResult,
                        isReady: true
                    ))
                default:
                    break
            }
        }
        return result
    }

    /// Convenience — checks the orchestrator's revealed set. Centralized
    /// so the various `messageRow` branches use the same key shape.
    private func isElementVisible(_ id: String) -> Bool {
        revealer.revealedIDs.contains(id)
    }

    /// Drives the `actionsVisible` state in response to streaming transitions.
    /// First run snaps to the current state (committed history mounts with
    /// actions already visible). Subsequent runs hide actions immediately when
    /// streaming starts, and reveal them after a short delay once streaming
    /// ends — long enough for the per-message masking animation to play out.
    /// `.task(id:)` cancels this task automatically if the streaming state
    /// flips again during the sleep, so a quick stream-restart won't reveal
    /// actions in the middle of the next round.
    @MainActor
    private func scheduleActionsVisibility(isLiveTrailing: Bool) async {
        if !actionsTimingBootstrapped {
            actionsTimingBootstrapped = true
            actionsVisible = !isLiveTrailing
            return
        }
        if isLiveTrailing {
            actionsVisible = false
            return
        }
        try? await Task.sleep(for: Self.actionRevealDelay)
        guard !Task.isCancelled else { return }
        // Plain assignment — fade-in is driven by `.animation(_:value:)` on
        // the row's opacity, no nested `withAnimation` + `.delay` needed.
        actionsVisible = true
    }

    // MARK: - Per-message rendering

    @MainActor @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        if case .content(let c) = msg {
            switch c.role {
                case .tool:
                    if isElementVisible("toolresult:\(c.id)") {
                        ToolResultCard(content: c)
                            .transition(.opacity)
                    }
                case .assistant:
                    assistantMessage(c, isStreaming: msg.id == inflightID && isActive)
                default:
                    EmptyView()
            }
        }
    }

    @MainActor @ViewBuilder
    private func assistantMessage(_ c: ChatMessageContent, isStreaming: Bool) -> some View {
        let text = displayText(of: c)
        let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
        VStack(alignment: .leading, spacing: 6) {
            // Content IS orchestrator-gated, same as tool calls / results
            // — the whole round's reveal needs to be linear, otherwise
            // a follow-up message's content would pop in while the
            // previous message's tool calls are still mid-pacing. The
            // earlier "content invisible during streaming" symptom that
            // motivated removing this gate is now handled inside
            // `RoundRevealOrchestrator.update(_:)`, which synchronously
            // inserts the current-index element into `revealedIDs`
            // before returning — so the body's *next* render already
            // sees the gate open, no Task-scheduling gap.
            if (!text.isEmpty || isStreaming),
               isElementVisible("content:\(c.id)") {
                SmoothStreamingText(target: text, isStreaming: isStreaming)
                    .transition(.opacity)
            }
            ForEach(nonFinalCalls, id: \.id) { call in
                if isElementVisible("toolcall:\(c.id):\(call.id)") {
                    ToolCallCard(
                        call: call,
                        isActive: isStreaming,
                        isDenied: isCallDenied(call)
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Helpers

    /// True when the round contains a `.tool` observation message whose
    /// `toolCallId` matches `call.id` and whose body is the "User denied
    /// execution of '<tool>'" string our `AgentExecutor` injects on a
    /// `.deny` decision (see LLMCore/Agent/AgentExecutor.swift). We
    /// match on the prefix rather than full-string compare because the
    /// reason text varies (`user declined`, custom denial reasons,
    /// future i18n).
    ///
    /// Lives on the round view rather than on `ToolCall` itself
    /// because `ToolCall` is a value type from the protocol payload
    /// and doesn't know about its sibling tool messages.
    private func isCallDenied(_ call: ToolCall) -> Bool {
        messages.contains { msg in
            guard case .content(let c) = msg,
                  c.role == .tool,
                  c.toolCallId == call.id else { return false }
            return c.content?.hasPrefix("User denied execution of") == true
        }
    }

    /// Concatenated text of every assistant message in the round, joined
    /// by blank lines. Used by the action row's Copy button — a single
    /// LLM turn often produces several `.assistant` messages (intermediate
    /// reasoning + tool calls + final answer); copying just the last one
    /// loses the lead-up. Tool result rows (`.tool` role) are intentionally
    /// excluded — they're raw JSON observations, not user-facing text.
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

    /// What text to display for an assistant message — `final_answer` tool-call
    /// args (parsed) take precedence over plain `content`, falling back to
    /// content if no `final_answer` call is present. This keeps display
    /// consistent whether the LLM ships its answer as plain content or via the
    /// tool-call form.
    private func displayText(of c: ChatMessageContent) -> String {
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return c.content ?? ""
    }

    /// The last assistant message in this round — the "final answer" the user
    /// is reading. Action row (copy / regenerate / usage) is anchored to it.
    private var lastAssistantMessage: ChatMessage? {
        messages.last(where: { msg in
            guard case .content(let c) = msg else { return false }
            return c.role == .assistant
        })
    }

    /// The target for the action row — the last assistant message, but only
    /// once it's no longer streaming. While streaming we hide actions so the
    /// user doesn't copy a partial answer or try to regenerate mid-stream.
    private var actionRowTarget: ChatMessage? {
        guard let last = lastAssistantMessage else { return nil }
        if isActive && last.id == inflightID { return nil }
        return last
    }

    /// Whether any message in the round currently produces visible UI. Used to
    /// gate the loading row: while the round is `isActive` but nothing is
    /// visible (anti-tease collapse + no tool calls yet), we show "Thinking…".
    private var hasAnyVisibleContent: Bool {
        messages.contains(where: isMessageVisible)
    }

    /// Whether *any* message has accumulated some substance — content, tool
    /// calls, or a tool result. Distinguishes "stream just opened, nothing
    /// yet" (false) from "stream is mid-flight, current snippet collapsed by
    /// anti-tease" (true). The internal loading row only fires in the latter
    /// case so it doesn't collide with LLMKit's `.loading` group during the
    /// cold-start window.
    private var hasAnyMessageWithSubstance: Bool {
        messages.contains { msg in
            guard case .content(let c) = msg else { return false }
            switch c.role {
                case .tool:
                    return true
                case .assistant:
                    let text = displayText(of: c)
                    let hasTools = (c.toolCalls?.isEmpty == false)
                    return !text.isEmpty || hasTools
                default:
                    return false
            }
        }
    }

    private func isMessageVisible(_ msg: ChatMessage) -> Bool {
        guard case .content(let c) = msg else { return false }
        switch c.role {
            case .tool:
                return true
            case .assistant:
                let text = displayText(of: c)
                let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
                if !nonFinalCalls.isEmpty { return true }
                // Any text counts as visible — even a streaming snippet
                // that's still being throttled (`displayText` lags behind
                // `target` by up to 500 ms) shouldn't fall back to the
                // loading row, because text is on its way and the row's
                // mount/unmount churn is what we're trying to avoid.
                return !text.isEmpty
            default:
                return false
        }
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
                Text(usage.formatted())
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
        // .frame(height: 24)
    }

}

// MARK: - Copy button

/// Copy button with an inline "copied" confirmation: tapping flips the icon
/// to a checkmark, then reverts after a short pause. Lives in its own view so
/// the @State is local — the parent round doesn't need to know about it, and
/// rapid taps just restart the revert timer for this instance.
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
    /// Returns nil when self is empty — handy for chaining `if let`.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Live wrapper

/// Hosts the most-recent assistant round in a stable view position. Its
/// SwiftUI identity is preserved across the streaming → finished transition,
/// so the per-message `SmoothStreamingText` state (and its catch-up + fade
/// animations) survive `streamingStore.removeStream` cleanly.
///
/// `stream` is optional: when present, we forward its `objectWillChange`
/// through `StreamObserver` (a stable `@StateObject`) so the body re-evaluates
/// on each tick; when nil, the round renders statically (it's "pinned" in the
/// live slot until a new round pushes it out — handled at `AIChatView` layout
/// level).
///
/// The crucial trick is that the `body` always returns the **same shape** —
/// a single `AssistantRoundView` — regardless of whether `stream` is nil. We
/// cannot use `if let stream { ActiveBody } else { StaticBody }` here: SwiftUI's
/// `_ConditionalContent` treats the two branches as different views, and
/// switching branches at stream-end would unmount the inner `AssistantRoundView`
/// (and all its `SmoothStreamingText` state, defeating the whole point).
struct LiveAssistantRoundView: View {
    let committedMessages: [ChatMessage]
    let stream: LLMStreamingStateObject?
    var onRegenerate: ((String) -> Void)?
    var onStreamUpdate: (() -> Void)?

    @StateObject private var observer = StreamObserver()

    var body: some View {
        AssistantRoundView(
            messages: resolvedMessages,
            inflightID: observer.stream?.id,
            isActive: observer.stream.map { !$0.isFinished } ?? false,
            onRegenerate: onRegenerate
        )
        // Re-bind the observer whenever the `stream` parameter identity changes
        // (nil → non-nil, instance swap, non-nil → nil). `.task(id:)` cancels
        // the previous task and runs a new one each time the id changes; the
        // body just calls observe() and exits.
        .task(id: stream.map(ObjectIdentifier.init)) {
            observer.observe(stream)
        }
        .onChange(of: observer.stream?.content) { _ in
            onStreamUpdate?()
        }
    }

    /// Between `.tool` and the next `.assistant`, LLMKit commits the previous
    /// assistant message (with toolCalls) into `conversation.messages` but does
    /// *not* reset `streamState.id` / `toolCalls` — they still hold the prev
    /// values until the next assistant turn overwrites them. If we naively
    /// append the synthesized inflight here we end up with two messages
    /// sharing the same id, each rendering its own `ToolCallCard`. Skip the
    /// inflight whenever its id already lives in committed history; once the
    /// next turn fires, the stream gets a fresh id and the inflight resumes
    /// rendering normally.
    private var resolvedMessages: [ChatMessage] {
        guard let stream = observer.stream else { return committedMessages }
        if committedMessages.contains(where: { $0.id == stream.id }) {
            return committedMessages
        }
        let toolCalls = stream.toolCalls.isEmpty ? nil : stream.toolCalls
        let inflight = ChatMessage.content(.init(
            id: stream.id,
            role: .assistant,
            content: stream.content,
            files: stream.files,
            usage: nil,
            toolCalls: toolCalls
        ))
        return committedMessages + [inflight]
    }
}

/// Forwards an optional `LLMStreamingStateObject`'s `objectWillChange` as our
/// own. Letting `LiveAssistantRoundView` `@StateObject`-observe this instead
/// of `@ObservedObject`-observing the stream directly is what allows `stream`
/// to be optional without forcing a structural branch in the view tree.
@MainActor
private final class StreamObserver: ObservableObject {
    private(set) var stream: LLMStreamingStateObject?
    private var cancellable: AnyCancellable?

    func observe(_ newStream: LLMStreamingStateObject?) {
        guard newStream !== stream else { return }
        // Signal *before* the mutation (Combine convention) so SwiftUI re-renders
        // any observer that depends on `stream`. Covers all three transitions:
        // nil → bound, bound → nil (round finished), bound → different bound.
        objectWillChange.send()
        stream = newStream
        cancellable = newStream?.objectWillChange.sink { [weak self] in
            // Republish each upstream tick so observers re-evaluate as new
            // chunks arrive.
            self?.objectWillChange.send()
        }
    }
}
