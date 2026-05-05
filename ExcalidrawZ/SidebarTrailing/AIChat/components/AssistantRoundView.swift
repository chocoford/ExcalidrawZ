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

    var body: some View {
        let actionTarget = actionRowTarget
        let isLiveTrailing = isActive && lastAssistantMessage?.id == inflightID
        let structureSig = makeStructureSignature(actionTargetID: actionTarget?.id)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { msg in
                messageRow(msg)
            }

            // Cover the gap when there's substance in flight but it's collapsed
            // by anti-tease (assistant text below threshold, no tool calls /
            // results yet either). Crucially we *don't* fire on the cold-start
            // window (no chunks at all yet) — `LLMStable.swift` puts a
            // `ChatMessage.loading()` into `conversation.messages` for that,
            // which `StaticGroupsView` renders. Without this guard we'd show
            // two "Thinking…" rows simultaneously until the first chunk lands
            // and LLMKit removes the loading message.
            if isActive && hasAnyMessageWithSubstance && !hasAnyVisibleContent {
                LoadingMessageRow()
                    .transition(.opacity)
            }

            if actionsVisible,
               let target = actionTarget,
               case .content(let c) = target,
               let text = displayText(of: c).nonEmpty {
                actionRow(text: text, sourceID: c.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.35), value: structureSig)
        .task(id: isLiveTrailing) {
            await scheduleActionsVisibility(isLiveTrailing: isLiveTrailing)
        }
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
        withAnimation(.easeIn(duration: 0.5).delay(1)) {
            actionsVisible = true
        }
    }

    // MARK: - Per-message rendering

    @MainActor @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        if case .content(let c) = msg {
            switch c.role {
                case .tool:
                    ToolResultCard(content: c)
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
            if !text.isEmpty {
                // SmoothStreamingText itself handles the anti-tease collapse
                // when isStreaming + text-too-short — we don't gate it here.
                SmoothStreamingText(target: text, isStreaming: isStreaming)
            }
            ForEach(nonFinalCalls, id: \.id) { call in
                ToolCallCard(call: call, isActive: isStreaming)
            }
        }
    }

    // MARK: - Helpers

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
                if text.isEmpty { return false }
                let isStreamingThis = msg.id == inflightID && isActive
                if isStreamingThis && !SmoothStreamingText.isMeaningfulLiveSnippet(text) {
                    return false
                }
                return true
            default:
                return false
        }
    }

    /// Compact signature of the round's *structure* (which messages exist + is
    /// the action row visible). Drives `.animation(value:)` so SwiftUI animates
    /// insertions/removals. Body content changes inside cards (eg streaming
    /// text) are *not* captured — those animate at their own cadence.
    private func makeStructureSignature(actionTargetID: String?) -> String {
        let ids = messages.map(\.id).joined(separator: ",")
        return "\(ids)|a=\(actionTargetID ?? "-")"
    }

    // MARK: - Action row

    @MainActor @ViewBuilder
    private func actionRow(text: String, sourceID: String) -> some View {
        HStack(spacing: 0) {
            CopyButton(text: text)

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
