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

import SwiftUI
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
    let revealsCommittedMessages: Bool
    let playsInitialReveal: Bool
    let keepsLoadingPlaceholderDuringReveal: Bool
    let onRegenerate: ((String) -> Void)?
    
    init(
        messages: [ChatMessage],
        isActive: Bool = false,
        revealsCommittedMessages: Bool = false,
        playsInitialReveal: Bool = false,
        keepsLoadingPlaceholderDuringReveal: Bool = false,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.messages = messages
        self.isActive = isActive
        self.revealsCommittedMessages = revealsCommittedMessages
        self.playsInitialReveal = playsInitialReveal
        self.keepsLoadingPlaceholderDuringReveal = keepsLoadingPlaceholderDuringReveal
        self.onRegenerate = onRegenerate
    }
    
    /// How long after the committed answer is revealed we wait before showing the
    /// action row (copy / regenerate / usage). Lets the trailing message's
    /// fade-in complete first so the action chrome doesn't sneak in
    /// before the user has read the answer.
    private static let actionRevealDelay: Duration = .milliseconds(400)
    private static let messageRevealAnimation: Animation = .easeOut(duration: ChatScrollAnimation.revealDuration)
    
    @State private var actionsVisible: Bool = false
    @State private var revealedMessageIDs: Set<String> = []
    /// Tracks whether `.task(id:)` has run at least once. The first run sets
    /// the initial visibility synchronously (no delay) so committed-history
    /// rounds — which mount with the round already finished — show actions
    /// immediately rather than after a needless delay.
    @State private var actionsTimingBootstrapped: Bool = false
    @State private var messageRevealBootstrapped: Bool = false
    
    /// Measured natural height of the round body. The committed message is
    /// mounted invisibly first, which gives the scroll host its final height
    /// before the reveal animation starts.
    @State private var roundHeight: CGFloat = 0
    @State private var hasInitializedRoundHeight: Bool = false
    
    var body: some View {
        if revealsCommittedMessages {
            animatedRoundBody
        } else {
            staticRoundBody
        }
    }
    
    private var staticRoundBody: some View {
        roundContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: isActive) {
                await scheduleActionsVisibility(isActive: isActive)
            }
    }
    
    private var animatedRoundBody: some View {
        ZStack(alignment: .top) {
            roundContent
                .frame(maxWidth: .infinity, alignment: .leading)
            // Force the inner VStack to its natural height — otherwise it
            // would size to whatever the outer Animatable frame proposes,
            // and `readHeight` would just echo that proposal back, killing
            // the interpolation we want.
                .fixedSize(horizontal: false, vertical: true)
        }
        // Read the natural height of the inner content, then constrain
        // the outer ZStack to that height via the Animatable modifier.
        // SwiftUI animates `roundHeight` transitions through the modifier,
        // which propagates to `NSHostingView.intrinsicContentSize` —
        // that's what the scroll host's `frameDidChange` observer needs
        // to see a smooth grow.
        .readHeight($roundHeight)
        .modifier(AssistantRoundHeightModifier(height: roundHeight))
        .animation(
            hasInitializedRoundHeight
            ? .smooth(duration: ChatScrollAnimation.revealDuration)
            : nil,
            value: roundHeight
        )
        .clipped()
        .onChange(of: roundHeight) { newHeight in
            guard newHeight > 0, !hasInitializedRoundHeight else { return }
            hasInitializedRoundHeight = true
        }
        .task(id: isActive) {
            await scheduleActionsVisibility(isActive: isActive)
        }
        // Re-run reveal scheduling when *either* the id sequence or any
        // message's "displayable content" presence flips. The latter is
        // what catches the moment a stub-with-no-content commits with
        // real text — id is unchanged but the message becomes revealable.
        .task(id: revealSignature) {
            await scheduleMessageReveal()
        }
    }
    
    private var roundContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            messagesContent
            
            if !isActive,
               hasRevealedAllMessages,
               let target = lastAssistantMessage,
               case .content(let c) = target,
               displayText(of: c).nonEmpty != nil {
                actionRow(
                    copyText: aggregatedAssistantText,
                    sourceID: c.id
                )
                .opacity(actionsVisible ? 1 : 0)
                .allowsHitTesting(actionsVisible)
                .animation(.easeInOut(duration: 0.3), value: actionsVisible)
            }
        }
    }
    
    private var messagesContent: some View {
        ForEach(messages) { msg in
            let isRevealed = isMessageRevealed(msg)
            messageRow(msg, isRevealed: isRevealed)
                .modifier(ConditionalChatTopDownReveal(progress: isRevealed ? 1 : 0, isEnabled: revealsCommittedMessages))
                .transition(.opacity)
        }
    }
    
    private var hasRevealedAllMessages: Bool {
        guard revealsCommittedMessages else { return true }
        return Set(messages.map(\.id)).isSubset(of: revealedMessageIDs)
    }
    
    private func isMessageRevealed(_ msg: ChatMessage) -> Bool {
        guard revealsCommittedMessages else { return true }
        return revealedMessageIDs.contains(msg.id)
    }
    
    /// Stable signature of the messages list that flips whenever a
    /// message gains or loses displayable content (text or tool calls).
    /// Used as the `.task(id:)` key for `scheduleMessageReveal` so that
    /// commit-time content changes (without id changes — LLMKit reuses
    /// the stream id on commit) still re-fire the reveal logic.
    private var revealSignature: [String] {
        messages.map { msg in
            if case .content(let c) = msg {
                let displayable = !displayText(of: c).isEmpty
                || !((c.toolCalls ?? []).isEmpty)
                return "\(msg.id):\(displayable ? 1 : 0)"
            }
            return msg.id
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
            actionsVisible = !isActive && hasRevealedAllMessages
            return
        }
        if isActive {
            actionsVisible = false
            return
        }
        await revealActionsIfReady()
    }
    
    @MainActor
    private func scheduleMessageReveal() async {
        let currentIDs = Set(messages.map(\.id))
        // Only messages with displayable content (text or tool calls) are
        // candidates for reveal. The `LoadingMessageRow` covers the "no
        // content yet" stretch; revealing an empty message would just play
        // the mask animation on nothing.
        let displayableIDs: Set<String> = Set(messages.compactMap { msg -> String? in
            if case .content(let c) = msg,
               !displayText(of: c).isEmpty || !((c.toolCalls ?? []).isEmpty) {
                return msg.id
            }
            return nil
        })
        
        // Drop ids that no longer exist in the round (e.g., truncated).
        revealedMessageIDs = revealedMessageIDs.intersection(currentIDs)
        
        guard revealsCommittedMessages else {
            revealedMessageIDs = displayableIDs
            messageRevealBootstrapped = true
            return
        }
        
        if !messageRevealBootstrapped {
            messageRevealBootstrapped = true
            // Mounting an existing round (e.g., committed history): everything
            // displayable is already settled, snap them in without delay.
            if playsInitialReveal {
                revealedMessageIDs = []
            } else {
                revealedMessageIDs = displayableIDs
            }
        }
        
        let pendingIDs = displayableIDs.subtracting(revealedMessageIDs)
        guard !pendingIDs.isEmpty else {
            return
        }
        
        try? await Task.sleep(for: .seconds(ChatScrollAnimation.scrollDuration))
        guard !Task.isCancelled else { return }
        
        withAnimation(Self.messageRevealAnimation) {
            revealedMessageIDs.formUnion(pendingIDs)
        }
        await revealActionsIfReady()
    }

    @MainActor
    private func revealActionsIfReady() async {
        guard !isActive, hasRevealedAllMessages else { return }
        try? await Task.sleep(for: Self.actionRevealDelay)
        guard !Task.isCancelled else { return }
        actionsVisible = true
    }
    
    // MARK: - Per-message rendering
    
    @MainActor @ViewBuilder
    private func messageRow(_ msg: ChatMessage, isRevealed: Bool) -> some View {
        if case .content(let c) = msg {
            switch c.role {
                case .tool:
                    ToolResultCard(content: c)
                case .assistant:
                    assistantMessage(c, isRevealed: isRevealed)
                default:
                    EmptyView()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func assistantMessage(_ c: ChatMessageContent, isRevealed: Bool) -> some View {
        let text = displayText(of: c)
        let nonFinalCalls = (c.toolCalls ?? []).filter { $0.name != "final_answer" }
        // Render only when there's something to show. The round-level
        // `LoadingMessageRow` (mounted by `body` when `isActive`) covers
        // the "still streaming, nothing committed yet" case — we deliberately
        // don't stack a per-message loading indicator here, so the
        // `chatTopDownReveal` mask doesn't have to worry about hiding
        // a busy-dots row, and the round's height swap stays a clean
        // structural transition rather than a `max(loading_h, real_h)`
        // ZStack collapse.
        if !text.isEmpty || !nonFinalCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !text.isEmpty {
                    // `isStreaming: false` — message is already committed
                    // (or is the synthesized stub for a tool-call-bearing
                    // stream, in which case the partial content is treated
                    // as static for rendering purposes).
                    SmoothStreamingText(target: text, isStreaming: false)
                }
                ForEach(nonFinalCalls, id: \.id) { call in
                    ToolCallCard(
                        call: call,
                        isActive: false,
                        isDenied: isCallDenied(call)
                    )
                    .onAppear {
                        // Republish to `AIChatState` so `ApprovalPromptView`'s
                        // gate can see the card has been mounted before
                        // unfurling its prompt.
                        aiChatState.markToolCallRevealed(call.id)
                    }
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

private struct ConditionalChatTopDownReveal: ViewModifier {
    let progress: CGFloat
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        if isEnabled {
            content.chatTopDownReveal(progress: progress)
        } else {
            content
        }
    }
}

// MARK: - Animatable round-height modifier

/// Wraps the round body in an Animatable frame whose height tracks the
/// inner content's natural size (read via `.readHeight`). The Animatable
/// `animatableData` is what makes SwiftUI propagate the height change to
/// `NSHostingView.intrinsicContentSize` *as a continuous interpolation*
/// — without it, AppKit autolayout sees a stepwise old → new size jump
/// and the scroll host's `frameDidChange` observer fires once with the
/// final value, missing the smooth-grow trajectory we want during the
/// `LoadingMessageRow → committed message` swap.
private struct AssistantRoundHeightModifier: Animatable, ViewModifier {
    init(height: CGFloat) {
        self.animatableData = height
    }
    
    var animatableData: CGFloat
    
    func body(content: Content) -> some View {
        content.frame(height: animatableData, alignment: .top)
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
