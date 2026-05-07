//
//  AssistantRoundView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  Per-message reveal: each entry in `messages` corresponds to one
//  LLMKit-committed `ChatMessage`. Insertions / removals animate via
//  SwiftUI's `.transition(.opacity)` paired with an `.animation(_:value:)`
//  keyed on the message-id sequence. No element-level orchestrator,
//  no streaming-text catch-up — just "a new committed message fades
//  in cleanly."
//
//  Why we ripped out `RoundRevealOrchestrator` + `inflightID`:
//    - With per-message granularity, every element of a freshly-
//      committed assistant message lands together (text + tool calls).
//      There's no value in pacing them separately.
//    - The orchestrator gated rendering on `isElementVisible(...)`
//      via `revealedIDs`; until the element entered that set, the
//      view returned `EmptyView`. If the orchestrator's `update(...)`
//      never fired for whatever reason, the message stayed invisible.
//    - `inflightID = streamState.id` matched the just-committed
//      message's id (LLMKit reuses the stream's id on commit), which
//      pushed `isStreaming=true` into `SmoothStreamingText` for an
//      *already-static* text — leaving the text masked for the
//      catch-up animation that never had data to catch up to.
//
//  `LiveAssistantRoundView` is the streaming wrapper: it observes the
//  in-flight stream object so `isActive` flips correctly when the
//  round finishes, and forwards committed messages through.
//

import SwiftUI
import Combine
import LLMCore
import LLMKit
import ChocofordUI
import SmoothGradient
#if canImport(AppKit)
import AppKit
#endif

struct AssistantRoundView: View {
    /// App-level chat state — used to publish tool-call reveals out so
    /// `ApprovalPromptView` knows the corresponding card has been shown
    /// before unfurling its prompt.
    @EnvironmentObject private var aiChatState: AIChatState

    let messages: [ChatMessage]
    let isActive: Bool
    let onRegenerate: ((String) -> Void)?

    init(
        messages: [ChatMessage],
        isActive: Bool = false,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.messages = messages
        self.isActive = isActive
        self.onRegenerate = onRegenerate
    }

    /// How long after `isActive` flips false we wait before showing the
    /// action row (copy / regenerate / usage). Lets the trailing message's
    /// fade-in complete first so the action chrome doesn't sneak in
    /// before the user has read the answer.
    private static let actionRevealDelay: Duration = .milliseconds(400)

    @State private var actionsVisible: Bool = false
    /// Tracks whether `.task(id:)` has run at least once. The first run sets
    /// the initial visibility synchronously (no delay) so committed-history
    /// rounds — which mount with the round already finished — show actions
    /// immediately rather than after a needless delay.
    @State private var actionsTimingBootstrapped: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { msg in
                messageRow(msg)
                    .transition(.messageReveal)
            }

            // "Thinking..." while the round is active and nothing has
            // been committed yet. Once the first message lands the
            // condition flips false and this row fades out as the
            // committed row fades in.
            if isActive && !hasAnyVisibleContent {
                LoadingMessageRow()
                    .transition(.opacity)
            }

            if let target = lastAssistantMessage,
               case .content(let c) = target,
               displayText(of: c).nonEmpty != nil {
                // Copy aggregates across the whole round (every assistant
                // message's text joined by blank lines) so a multi-step
                // turn copies all the reasoning + final answer in order.
                // Regenerate is anchored to the trailing message because
                // LLMKit's `regenerate(fromMessageID:)` walks back from
                // there.
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
        // Drives the per-row insertion/removal animation. Keying on
        // the id sequence — not on `messages` directly — keeps the
        // animation triggered for structural changes only, ignoring
        // in-place mutations like `usage` updates.
        .animation(.easeOut(duration: 0.25), value: messages.map(\.id))
        .task(id: isActive) {
            await scheduleActionsVisibility(isActive: isActive)
        }
    }

    /// Drives the `actionsVisible` state in response to round transitions.
    /// First run snaps to the current state (committed history mounts
    /// with actions already visible). Subsequent runs hide actions
    /// immediately when the round becomes active and reveal them after
    /// a short delay once it ends.
    @MainActor
    private func scheduleActionsVisibility(isActive: Bool) async {
        if !actionsTimingBootstrapped {
            actionsTimingBootstrapped = true
            actionsVisible = !isActive
            return
        }
        if isActive {
            actionsVisible = false
            return
        }
        try? await Task.sleep(for: Self.actionRevealDelay)
        guard !Task.isCancelled else { return }
        actionsVisible = true
    }

    // MARK: - Per-message rendering

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
        VStack(alignment: .leading, spacing: 6) {
            if !text.isEmpty {
                // `isStreaming: false` — message is already committed,
                // SmoothStreamingText just renders the text statically.
                // (We could swap to a plain Markdown later; keeping the
                // wrapper for now avoids touching the rendering chain.)
                SmoothStreamingText(target: text, isStreaming: false)
            }
            ForEach(nonFinalCalls, id: \.id) { call in
                ToolCallCard(
                    call: call,
                    isActive: false,
                    isDenied: isCallDenied(call)
                )
                .onAppear {
                    // Republish to AIChatState so `ApprovalPromptView`'s
                    // gate (if it still uses one) can see the card has
                    // been mounted before unfurling.
                    aiChatState.markToolCallRevealed(call.id)
                }
            }
        }
    }

    // MARK: - Helpers

    /// True when the round contains a `.tool` observation message whose
    /// `toolCallId` matches `call.id` and whose body is the "User denied
    /// execution of '<tool>'" string our `AgentExecutor` injects on a
    /// `.deny` decision.
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
    /// loses the lead-up.
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
    /// content if no `final_answer` call is present.
    private func displayText(of c: ChatMessageContent) -> String {
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return c.content ?? ""
    }

    /// The last assistant message in this round — the "final answer" the
    /// user is reading. Action row (copy / regenerate / usage) anchors here.
    private var lastAssistantMessage: ChatMessage? {
        messages.last(where: { msg in
            guard case .content(let c) = msg else { return false }
            return c.role == .assistant
        })
    }

    /// Whether any message in the round currently produces visible UI.
    /// Drives the loading row: while `isActive` and nothing is visible
    /// yet, we show "Thinking…".
    private var hasAnyVisibleContent: Bool {
        messages.contains(where: isMessageVisible)
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
    }
}

// MARK: - Message reveal mask

/// Top-down mask reveal driven by an `Animatable` ratio (0...1).
///
/// Mask layout (top to bottom):
///   1. `Color.black` — opaque "revealed" region; height grows from
///      0 to the full content height as the transition runs.
///   2. `SmoothLinearGradient` strip — **fixed** height
///      (`Self.stripHeight`); slides down on top of the revealed
///      region as the leading edge of the wipe. Provides the soft
///      fade so the boundary doesn't pop.
///   3. `Color.clear` — "hidden" region; height shrinks from
///      `(contentHeight - stripHeight)` to 0.
///
/// Why a fixed strip and a separate Color.clear: scaling the gradient
/// itself (the previous version) made the strip stretch over the
/// entire row, which spread the fade thin and the leading edge read
/// as a gentle dim rather than a wipe. With a fixed strip the
/// fade has a constant visual thickness throughout, giving the
/// reveal a clearer "scanline" feel.
///
/// Final phase: once `Color.clear` collapses to 0 (i.e. revealed
/// height has eaten everything except the strip), the strip itself
/// shrinks the rest of the way so the mask ends at fully opaque
/// `Color.black`.
private struct MessageRevealMaskModifier: ViewModifier, Animatable {
    /// 0 = hidden (only the gradient strip is opaque, everything
    /// below it is clear and the row is invisible). 1 = fully
    /// revealed (mask is solid `Color.black`).
    var animatableData: CGFloat = 0

    /// Vertical thickness of the soft "fade strip" while it's
    /// scanning down. Stays constant for the bulk of the animation;
    /// only shrinks once the revealed `Color.black` region has
    /// reached `contentHeight - stripHeight`.
    private static let stripHeight: CGFloat = 30

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                let H = proxy.size.height
                let revealed = max(0, min(1, animatableData))
                let blackHeight = H * revealed
                let remaining = max(0, H - blackHeight)
                // Strip stays at `stripHeight` until the wipe nears
                // the bottom edge; then it collapses with `remaining`.
                let strip = min(Self.stripHeight, remaining)
                let clear = max(0, remaining - strip)

                VStack(spacing: 0) {
                    Color.black.frame(height: blackHeight)
                    fadeStrip.frame(height: strip)
                    Color.clear.frame(height: clear)
                }
            }
        }
    }

    @ViewBuilder
    private var fadeStrip: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            SmoothLinearGradient(
                from: .black,
                to: .clear,
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension AnyTransition {
    /// Top-down gradient mask reveal — applied to each message row when
    /// it commits into the round. `active` is "row hidden, fade strip
    /// at the very top"; `identity` is "fully revealed, mask is a
    /// no-op".
    static var messageReveal: AnyTransition {
        .modifier(
            active: MessageRevealMaskModifier(animatableData: 0),
            identity: MessageRevealMaskModifier(animatableData: 1)
        )
    }
}

// MARK: - Copy button

/// Copy button with an inline "copied" confirmation: tapping flips the icon
/// to a checkmark, then reverts after a short pause.
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

// MARK: - Live wrapper

/// Hosts the trailing assistant round and forwards committed messages
/// to `AssistantRoundView`. Observes the in-flight stream via
/// `StreamObserver` so `isActive` flips correctly when the round
/// finishes (no per-token side effects — we don't peek at the stream
/// content, just at its `isFinished` flag through the observer).
struct LiveAssistantRoundView: View {
    let committedMessages: [ChatMessage]
    let stream: LLMStreamingStateObject?
    var onRegenerate: ((String) -> Void)?

    @StateObject private var observer = StreamObserver()

    var body: some View {
        AssistantRoundView(
            messages: resolvedMessages,
            isActive: observer.stream.map { !$0.isFinished } ?? false,
            onRegenerate: onRegenerate
        )
        .task(id: stream.map(ObjectIdentifier.init)) {
            observer.observe(stream)
        }
    }

    /// We render committed messages by default — the per-message
    /// granularity rule. The exception is when the stream has tool
    /// calls in flight but the assistant message hasn't committed
    /// yet: LLMKit holds the message between "model emitted tool
    /// calls" and "tool finished executing", which for tools that
    /// require approval can be an indefinite wait. Without an
    /// inflight synthesis the user sees only the loading row + the
    /// approval prompt — they can't see *what tool* the model
    /// actually wants to run beyond the small badge in the prompt.
    /// Synthesise an inflight for that window so the `ToolCallCard`
    /// renders above the approval prompt.
    ///
    /// Pure text streaming (no tool calls in the stream yet) does
    /// NOT synthesize — that preserves the per-message rule for the
    /// common case and keeps SmoothStreamingText off the per-token
    /// path we explicitly walked away from.
    private var resolvedMessages: [ChatMessage] {
        guard let stream = observer.stream, !stream.isFinished else {
            return committedMessages
        }
        guard !stream.toolCalls.isEmpty else {
            return committedMessages
        }
        // If LLMKit *did* already commit (e.g. for tools that don't
        // need approval, the commit lands ~instantly before we render),
        // skip the synthesis so we don't double-add the same id.
        if committedMessages.contains(where: { $0.id == stream.id }) {
            return committedMessages
        }
        let inflight = ChatMessage.content(.init(
            id: stream.id,
            role: .assistant,
            content: stream.content,
            files: stream.files,
            usage: nil,
            toolCalls: stream.toolCalls
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
        objectWillChange.send()
        stream = newStream
        cancellable = newStream?.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
