//
//  AIChatIslandView.swift
//  ExcalidrawZ
//
//  Floating, draggable companion to `AIChatView`. Same conversation, smaller
//  footprint. While a reply is streaming the latest in-flight assistant text
//  appears above the input; once finished the bubble collapses so the island
//  stays compact.
//

import SwiftUI
import LLMKit
import LLMCore
import SFSafeSymbols
import ChocofordUI

struct AIChatIslandView: View {
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState

    /// Editor (parent) size, fed in from `ExcalidrawEditor` via a background
    /// `GeometryReader`. Used to clamp the drag offset back inside the editor
    /// 1 s after the user releases. `.zero` is treated as "not yet measured"
    /// and disables clamping.
    let canvasSize: CGSize

    /// In-flight drag delta. Combined with `layoutState.aiChatIslandOffset` to
    /// produce the visual position. On gesture end we fold the delta into the
    /// persisted offset so the island stays put after the next remount.
    @GestureState private var dragDelta: CGSize = .zero

    /// Measured island height. Width is fixed (`islandWidth`) but height
    /// varies with the streaming preview / input growth — needed for the
    /// clamp math to know if the top edge would clip the editor.
    @State private var measuredHeight: CGFloat = 0

    /// Pending snap-back task — cancelled on every drag end so only the
    /// latest release fires the 1 s delayed clamp.
    @State private var snapBackTask: Task<Void, Never>?

    /// Single-line reply ticker shown while a round is in progress and for
    /// `tickerDuration` after each reply commits. Lifecycle: "Thinking…"
    /// while the round has no committed assistant message; swapped to the
    /// committed message text on each commit; for messages with non-final
    /// tool calls the text further switches from content → tool-call after
    /// `toolCallSwitchDelay`. The mask animation lives inside
    /// `ReplyTickerView` and re-fires every time this string changes.
    @State private var displayedReplyText: String?

    /// Pending "ticker → banner" revert. Cancelled if a new round starts or
    /// the view disappears, so a long answer landing right before unmount
    /// doesn't leak a delayed mutation onto a torn-down state.
    @State private var autoHideTask: Task<Void, Never>?

    /// Pending "content → tool call display" swap. When a committed
    /// message has a non-final-answer tool call alongside content, we
    /// linger on the content for `toolCallSwitchDelay` then switch to
    /// the tool-call frame.
    @State private var toolCallSwitchTask: Task<Void, Never>?

    /// Last assistant message id we've already pushed into the ticker.
    /// Used to dedupe `latestAssistantMessageID` onChange firings against
    /// re-renders for unrelated state changes.
    @State private var lastSeenAssistantMessageID: String?


    /// How long the ticker lingers after a round finishes before the header
    /// reverts to the credits banner. 3 s is enough to read a one-line
    /// final answer at glance speed without making the banner-revert feel
    /// late; shorter and the user is still parsing the text when it pops.
    private let tickerDuration: Duration = .seconds(3)

    /// How long to show a message's content before swapping to the tool-call
    /// frame for messages that carry a non-final-answer tool call.
    private let toolCallSwitchDelay: Duration = .seconds(1)

    private let islandWidth: CGFloat = 420
    private let previewMaxHeight: CGFloat = 200
    /// How close to the editor edge the island is allowed to settle after a
    /// clamp — small breathing room so it doesn't visually kiss the border.
    private let edgeMargin: CGFloat = 8
    /// Default bottom inset between island and editor bottom (set by the
    /// `.padding(.bottom, 24)` in `ExcalidrawEditor`'s overlay). Mirrored
    /// here because the clamp math needs to anchor the y baseline.
    private let bottomPadding: CGFloat = 24
    /// How long after a drag release we wait before snapping back.
    private let snapBackDelay: Duration = .seconds(1)

    /// Bridges the `FileState`-owned conversation id to `PromptInputView`'s
    /// `Binding<String?>` API. `PromptInputView` mutates this when it creates
    /// a fresh conversation on first send.
    private var conversationIDBinding: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }

    private var hasActiveGeneration: Bool {
        guard let conversationID = fileState.aiChatConversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
            || activeStreamingAssistantContent != nil
    }

    /// Mirror of `ApprovalPromptView`'s gate so the island's
    /// `.animation(value:)` knows to animate the layout shift when
    /// the card flips visibility.
    private var shouldShowApprovalCard: Bool {
        llmState.pendingApprovalRequest != nil
    }

    /// Same indicator gate as `AIChatView` — visible while LLMKit's
    /// compact call is in flight on this surface's conversation.
    private var isCompactingThisConversation: Bool {
        aiChatState.isCompacting(conversationID: fileState.aiChatConversationID)
    }

    private var conversation: Conversation? {
        llmState.conversations.value?
            .first { $0.id == fileState.aiChatConversationID }
    }

    private var activeStreamingAssistantContent: ChatMessageContent? {
        guard let conversationID = fileState.aiChatConversationID,
              let messages = conversation?.messages else {
            return nil
        }
        return messages.compactMap { message -> ChatMessageContent? in
            guard case .content(let content) = message,
                  content.role == .assistant,
                  llmState.isStreaming(messageID: content.id, in: conversationID) else {
                return nil
            }
            return content
        }.last
    }

    /// The latest *committed* (not currently streaming) assistant message.
    /// We need the full message — not just its display text — so we can
    /// branch on whether it carries non-final-answer tool calls.
    private var latestAssistantMessage: ChatMessage? {
        guard let conversationID = fileState.aiChatConversationID,
              let messages = conversation?.messages else {
            return nil
        }
        return messages.last { msg in
            guard case .content(let c) = msg,
                  c.role == .assistant else {
                return false
            }
            if llmState.isStreaming(messageID: c.id, in: conversationID) {
                return false
            }
            return true
        }
    }

    /// Stable id for `latestAssistantMessage`. Watched by `.onChange` to
    /// detect "a new assistant message just committed".
    private var latestAssistantMessageID: String? {
        latestAssistantMessage?.id
    }

    private func displayText(of c: ChatMessageContent) -> String {
        if let finalCall = c.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return c.content ?? ""
    }

    /// Single-line label for a tool-call frame in the ticker. Resolve the
    /// protocol-level snake_case name to the same display name used by the
    /// full `ToolCallCard`, so the island does not leak internal tool ids.
    private func toolCallDisplay(_ name: String) -> String {
        String(
            localizable: .aiChatToolCallDisplay(ToolDisplayNameCache.displayName(for: name))
        )
    }

    /// Name of the first non-final-answer tool call currently being emitted
    /// in the active stream (or nil when no stream is active or only the
    /// `final_answer` synthetic call is present). LLMKit keeps streaming
    /// content/tool calls on `conversation.messages`.
    private var liveToolCallName: String? {
        activeStreamingAssistantContent?.toolCalls?
            .first(where: { $0.name != "final_answer" })?
            .name
    }

    /// Show the streaming preview only while the assistant is actively
    /// generating *and* has produced enough text to be meaningful — same
    /// threshold as the inspector view, so the user doesn't see "OK!" flash
    /// here either.
    private var visibleStreamingText: String? {
        if let content = activeStreamingAssistantContent {
            let text = displayText(of: content)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 10) {
            islandHeader()
            
            islandBody()
        }
        .offset(
            x: layoutState.aiChatIslandOffset.width + dragDelta.width,
            y: layoutState.aiChatIslandOffset.height + dragDelta.height
        )
        .animation(.easeInOut(duration: 0.25), value: visibleStreamingText != nil)
        .animation(.easeInOut(duration: 0.25), value: displayedReplyText != nil)
        // Window resize / split changes shrink `canvasSize` and may strand
        // the island outside the new bounds. Clamp immediately (no 1 s
        // delay) — there's no drag in flight to wait for.
        .onChange(of: canvasSize, debounce: 1) { _ in
            snapBackTask?.cancel()
            snapBackIfOutOfBounds()
        }
        // Watch only the *boundary* of the run lifecycle (active ↔ idle).
        // Token-level streaming can pause around tool calls; `isRunning`
        // remains true through those seams.
        .onAppear {
            updateGenerationTicker(hasActiveGeneration: hasActiveGeneration)
        }
        .onChange(of: hasActiveGeneration) { active in
            updateGenerationTicker(hasActiveGeneration: active)
        }
        // Real-time tool-call surfacing. The streaming message accumulates
        // tool calls before the message itself commits; reflecting that
        // immediately means "Thinking…" flips to "Using <tool>…" the moment
        // the model fires the call, instead of lingering until the message
        // lands in `conversation.messages`. We also guard against beating
        // a same-named display already on screen (no-op write).
        .onChange(of: liveToolCallName) { newName in
            guard let newName else { return }
            let label = toolCallDisplay(newName)
            guard displayedReplyText != label else { return }
            autoHideTask?.cancel()
            toolCallSwitchTask?.cancel()
            displayedReplyText = label
        }
        // Each new committed assistant message drives the ticker. We dedupe
        // against `lastSeenAssistantMessageID` so unrelated re-renders don't
        // re-process the same message and double-fire the timing chain.
        .onChange(of: latestAssistantMessageID) { newID in
            guard let newID, newID != lastSeenAssistantMessageID else { return }
            lastSeenAssistantMessageID = newID
            handleNewAssistantMessage()
        }
        .onDisappear {
            autoHideTask?.cancel()
            toolCallSwitchTask?.cancel()
        }
    }

    private func updateGenerationTicker(hasActiveGeneration: Bool) {
        if hasActiveGeneration {
            autoHideTask?.cancel()
            toolCallSwitchTask?.cancel()
            if displayedReplyText == nil {
                displayedReplyText = String(localizable: .aiChatThinking)
            }
        } else if displayedReplyText == String(localizable: .aiChatThinking) {
            autoHideTask?.cancel()
            toolCallSwitchTask?.cancel()
            displayedReplyText = nil
        }
    }

    @ViewBuilder
    private func islandHeader() -> some View {
        VStack {
            ZStack {
                if let text = displayedReplyText {
                    ReplyTickerView(text: text)
                        .transition(.opacity)
                } else {
                    LowCreditsBannerView()
                        .font(.body)
                        .transition(.opacity)
                }
            }
            .background {
                islandBackground(shape: Capsule())
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            }
            .frame(height: 36, alignment: .bottom)
            
            PendingQueueView(
                messages: aiChatState.pendingQueue,
                onRemove: { id in
                    withAnimation(.smooth(duration: 0.2)) {
                        aiChatState.pendingQueue.removeAll { $0.id == id }
                    }
                }
            )

        }
        .frame(width: islandWidth)
    }
    
    @ViewBuilder
    private func islandBody() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isCompactingThisConversation {
                CompactingIndicatorView()
                    .transition(.opacity)
            }

            // Self-gating: shows up only when LLMKit has a
            // `pendingApprovalRequest`. Animation on the parent VStack so
            // its insertion smoothly grows the island instead of popping.
            ApprovalPromptView()

            PromptInputView(
                conversationID: conversationIDBinding,
                pendingQueue: $aiChatState.pendingQueue,
                style: .island
            )
            .disabled(fileState.currentActiveFileIsInTrash)
        }
        .padding(16)
        // Drive on the gate result (`pendingApprovalRequest != nil`
        // AND the matching tool-call card revealed) — same reasoning
        // as `AIChatView`. A bare `pendingApprovalRequest?.id` value
        // would miss the gate-flipping-true layout change.
        .animation(
            .easeInOut(duration: 0.25),
            value: shouldShowApprovalCard
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: isCompactingThisConversation
        )
        .frame(width: islandWidth)
        .background {
            islandBackground(
                shape: RoundedRectangle(cornerRadius: 24),
                fallbackShape: RoundedRectangle(cornerRadius: 16)
            )
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
        }
        .readHeight($measuredHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
    
    // MARK: - Header / drag handle

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 4) {
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(localizable: .aiChatTitle)
                .foregroundStyle(.secondary)
                .font(.caption)

            Spacer()

            Button {
                layoutState.exitAIChatIsland()
            } label: {
                if #available(macOS 14.0, *) {
                    Image(systemSymbol: .arrowDownLeftAndArrowUpRight)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemSymbol: .arrowUpLeftAndArrowDownRight)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(.localizable(.aiChatButtonInspectMode))
        }
        .hoverCursor(.grabIdle, forceAppKit: true)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($dragDelta) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                layoutState.aiChatIslandOffset = CGSize(
                    width: layoutState.aiChatIslandOffset.width + value.translation.width,
                    height: layoutState.aiChatIslandOffset.height + value.translation.height
                )
                scheduleSnapBack()
            }
    }

    
    /// Process the just-committed assistant message: derive its initial
    /// frame (content text, or — if content is empty — the tool-call
    /// label), schedule the optional content→tool-call switch, and queue
    /// the auto-hide unless a tool call indicates more is coming.
    private func handleNewAssistantMessage() {
        guard let msg = latestAssistantMessage,
              case .content(let c) = msg else { return }

        autoHideTask?.cancel()
        toolCallSwitchTask?.cancel()

        let content = displayText(of: c)
        let nonFinalTool = c.toolCalls?.first(where: { $0.name != "final_answer" })

        if let nonFinalTool {
            // Tool-call message: surface content first (if any) so the user
            // sees what the model said before it fired the tool, then swap
            // to the tool-call label. Don't auto-hide — more messages are
            // expected later in the same round (tool result, then final
            // answer), each of which will retrigger this handler.
            //
            // If the live-stream watcher already pushed this exact tool's
            // display to the ticker, skip the content phase entirely —
            // bouncing back to "Let me search…" before re-arriving at
            // "Using web_search…" reads as a regression.
            let toolLabel = toolCallDisplay(nonFinalTool.name)
            let alreadyOnToolLabel = displayedReplyText == toolLabel
            if content.isEmpty || alreadyOnToolLabel {
                displayedReplyText = toolLabel
            } else {
                displayedReplyText = content
                toolCallSwitchTask = Task { @MainActor in
                    try? await Task.sleep(for: toolCallSwitchDelay)
                    guard !Task.isCancelled else { return }
                    displayedReplyText = toolLabel
                }
            }
            return
        }

        // Pure-content (or final_answer) message — terminal frame for the
        // round; show it briefly, then revert to the banner.
        guard !content.isEmpty else { return }
        displayedReplyText = content
        scheduleAutoHide()
    }

    /// Schedule the "ticker → banner" revert. Cancels any prior pending
    /// hide first so consecutive replies don't accidentally double-hide.
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: tickerDuration)
            guard !Task.isCancelled else { return }
            displayedReplyText = nil
        }
    }
    
    
    /// Cancel any pending snap-back, then queue a fresh one. The 1 s delay
    /// gives the user a beat to either drag again (which cancels this) or
    /// just see where they parked the island before it auto-corrects.
    private func scheduleSnapBack() {
        snapBackTask?.cancel()
        snapBackTask = Task { @MainActor in
            try? await Task.sleep(for: snapBackDelay)
            guard !Task.isCancelled else { return }
            snapBackIfOutOfBounds()
        }
    }

    /// Compute the in-bounds offset and animate to it if different. Skipped
    /// when sizes haven't been measured yet (first appear) or the editor is
    /// somehow smaller than the island, in which case we'd rather leave the
    /// user's chosen position alone than force a confusing nudge.
    @MainActor
    private func snapBackIfOutOfBounds() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        guard measuredHeight > 0 else { return }
        let islandSize = CGSize(width: islandWidth, height: measuredHeight)
        let clamped = clampedOffset(
            layoutState.aiChatIslandOffset,
            islandSize: islandSize,
            canvas: canvasSize
        )
        guard clamped != layoutState.aiChatIslandOffset else { return }
        withAnimation(.bouncy(duration: 0.5)) {
            layoutState.aiChatIslandOffset = clamped
        }
    }

    /// Clamp `offset` so the island stays inside the editor with `edgeMargin`
    /// breathing room. The default position (offset = .zero) is bottom-center
    /// at `bottomPadding` from the bottom edge — the math anchors the island's
    /// rect to that baseline before applying offset.
    private func clampedOffset(
        _ offset: CGSize,
        islandSize: CGSize,
        canvas: CGSize
    ) -> CGSize {
        // Horizontal: symmetrical around center. If the editor is narrower
        // than island + 2*margin (e.g. very thin window), allow zero range.
        let halfRangeX = max(0, (canvas.width - islandSize.width) / 2 - edgeMargin)
        let clampedDX = min(halfRangeX, max(-halfRangeX, offset.width))

        // Vertical: y origin (top of island) at offset (0,0) is
        //   canvas.height - bottomPadding - islandSize.height
        // Constraint: keep top.y >= edgeMargin AND bottom.y <= canvas.height - edgeMargin
        let maxDY = bottomPadding - edgeMargin
        let minDY = bottomPadding + islandSize.height - canvas.height + edgeMargin
        let clampedDY: CGFloat
        if minDY > maxDY {
            // Editor too small to fit island — don't fight the user, leave
            // y untouched.
            clampedDY = offset.height
        } else {
            clampedDY = min(maxDY, max(minDY, offset.height))
        }

        return CGSize(width: clampedDX, height: clampedDY)
    }

    // MARK: - Streaming preview

    @ViewBuilder
    private func streamingPreview(_ text: String) -> some View {
        ScrollView {
            Text(verbatim: text)
                .textSelection(.enabled)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: previewMaxHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.12))
        )
    }

    // MARK: - Background

    @ViewBuilder
    private func islandBackground<S: Shape>(
        shape: S
    ) -> some View {
        islandBackground(shape: shape, fallbackShape: shape)
    }
    
    @ViewBuilder
    private func islandBackground<S1: Shape, S2: Shape>(
        shape: S1,
        fallbackShape: S2
    ) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            fallbackShape
                .fill(.regularMaterial)
        }
    }
}

// MARK: - ReplyTickerView

/// Single-line ticker that shows the AI's most recent line in the island
/// header. Owns its own reveal animation: every time `text` changes, a
/// gradient mask sweeps left → right to give a "dictating" feel without
/// actually streaming character-by-character.
///
/// The mask is driven by a `TimelineView(.animation)` reading off a
/// `revealStart` Date that resets on every `text` change. Earlier
/// implementations animated a `revealProgress` `@State` via `withAnimation`
/// — but SwiftUI coalesces "reset to 0" + "animate to 1.1" sequential
/// writes into a single render, so subsequent reveals no-oped. Time-based
/// computation has no such batching pitfall.
struct ReplyTickerView: View {
    let text: String

    /// What the Text view actually renders. Decoupled from the `text` prop
    /// so the OLD text stays visible while we erase it; if Text bound
    /// directly to the prop, the swap would happen instantly and we'd
    /// erase the wrong characters. Flipped to the new value after the
    /// erase phase finishes.
    @State private var displayedText: String = ""

    /// Wall-clock anchor for the active phase. Each phase reads
    /// `(now - animationStart)` inside a `TimelineView` to compute its
    /// progress. Time-based driving sidesteps SwiftUI's `@State` write
    /// coalescing — earlier `withAnimation` versions no-oped on subsequent
    /// reveals because "reset to 0 then animate to 1.1" collapsed into
    /// a single render.
    ///
    /// Default value is `.now` (not `.distantPast`) so the very first
    /// render sees `elapsed ≈ 0` and the mask starts clear. With a far-past
    /// default, the first frame would compute `elapsed >> revealDuration`
    /// and clamp progress to its max — the initial "Thinking…" would flash
    /// fully-revealed for one frame before `onAppear` re-anchored the
    /// timeline, which is why the very first reveal looked like it skipped.
    @State private var animationStart: Date = .now

    /// Which way the mask is sweeping right now. `reveal` ramps mask 0→1.1
    /// (text writes in left→right), `erase` ramps it 1.1→0 (text drains
    /// right→left). Text swaps happen in between via `phaseSwitchTask`.
    @State private var phase: AnimationPhase = .reveal

    /// Pending "swap text and start reveal" hop, scheduled when an erase
    /// kicks off. Cancelled if a fresh text change arrives mid-erase so
    /// the latest target wins (we don't pile up dead writes).
    @State private var phaseSwitchTask: Task<Void, Never>?

    /// Mask progress at the moment we entered the current `.erase` phase.
    /// The erase ramps from this value (not always 1.1) down to 0, so
    /// switching mid-reveal — e.g. "Thinking…" hadn't fully revealed yet
    /// when the next text arrived — doesn't snap the mask up to fully
    /// solid before erasing. No snap, no flicker.
    @State private var eraseStartProgress: CGFloat = 1.1

    /// Continuously animated 0 → 360. `.hueRotation` makes the gradient's
    /// colors cycle through the wheel without ever needing a "snap" frame
    /// — at 360° the rendering is identical to 0° so `.repeatForever` loops
    /// seamlessly. Animating gradient stop positions instead would require
    /// either a tiled rectangle or accepting a visible loop discontinuity.
    @State private var hueRotation: Double = 0

    private enum AnimationPhase {
        case reveal
        case erase
    }

    /// How long the mask sweep takes from fully clear to fully solid.
    private let revealDuration: TimeInterval = 1.0

    /// How long the reverse sweep takes from a fully-solid mask. Slightly
    /// shorter than `revealDuration` — erasing is a transition, not the
    /// main event — but kept generous enough that the right→left wipe is
    /// clearly visible rather than a fleeting flash.
    private let eraseDuration: TimeInterval = 0.6

    /// If the mask is below this progress when a text change arrives, the
    /// old text wasn't really visible (still in mount delay, or barely
    /// past the reveal start) — skip the erase phase and just reveal the
    /// new text. Erasing something the user never saw reads as a glitch.
    private let eraseSkipThreshold: CGFloat = 0.15

    /// Delay before the reveal sweep starts on **first appearance**. The
    /// parent fades the ticker in via `.transition(.opacity)` over ~0.25s;
    /// without this delay the first quarter of the sweep happens while
    /// the ticker is still half-transparent and the eye misses it. Only
    /// applied on `.onAppear` (mount); subsequent in-place text swaps
    /// don't fade in, so they reveal immediately.
    private let initialMountDelay: TimeInterval = 0.3

    /// Keep this mapped to the shared AI token so island, paywall, and
    /// toolbar accents evolve as one visual family.
    private let progressGradient = AIAppearancePalette.thinkingGradient

    var body: some View {
        HStack(spacing: 6) {
            Image(systemSymbol: .sparkles)
                .foregroundStyle(progressGradient)
                .hueRotation(.degrees(hueRotation))
            Text(displayedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask { revealMask }
        .background { progressGlow }
        .onAppear {
            displayedText = text
            phase = .reveal
            // Push the anchor into the future so the mask stays fully clear
            // until the parent's opacity transition finishes. Negative
            // elapsed in `progress(at:)` is guarded → 0 → text invisible.
            animationStart = .now.addingTimeInterval(initialMountDelay)
            // Continuous color cycle. Loops seamlessly — 360° hue rotation
            // renders identically to 0°, so `.repeatForever` has no visible
            // snap on wrap.
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                hueRotation = 360
            }
        }
        .onChange(of: text) { newText in
            handleTextChange(newText)
        }
        .onDisappear {
            phaseSwitchTask?.cancel()
        }
    }

    /// Two-phase swap on text change: erase the old text, then reveal the
    /// new one. Three early-out cases:
    ///
    ///  - ticker was empty (initial mount edge case),
    ///  - prop matches what we're already showing (defensive),
    ///  - old text isn't actually visible yet (mount delay window or
    ///    reveal barely started) — erasing something invisible looks
    ///    like a flicker, not a wipe.
    ///
    /// In all three we skip the erase and reveal the new text directly.
    /// Otherwise, we capture the *current* mask progress as the erase's
    /// starting point (so a swap mid-reveal continues smoothly down
    /// rather than snapping back up to fully solid first), and scale the
    /// erase duration proportionally so the perceived speed stays
    /// constant whether we're erasing 1.1 → 0 or 0.6 → 0.
    private func handleTextChange(_ newText: String) {
        phaseSwitchTask?.cancel()

        let currentProgress = progress(at: .now)

        let needsErase = !displayedText.isEmpty
            && displayedText != newText
            && currentProgress >= eraseSkipThreshold

        guard needsErase else {
            displayedText = newText
            phase = .reveal
            animationStart = .now
            return
        }

        eraseStartProgress = currentProgress
        phase = .erase
        animationStart = .now

        // Scale duration so erasing from a partially-revealed mask still
        // feels like the same speed — going 0.5 → 0 in 0.6 s would look
        // sluggish; 0.5 / 1.1 * 0.6 ≈ 0.27 s is right.
        let scaledDuration = eraseDuration * Double(currentProgress / 1.1)

        phaseSwitchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(scaledDuration))
            guard !Task.isCancelled else { return }
            displayedText = newText
            phase = .reveal
            animationStart = .now
        }
    }

    /// Time-driven mask. `TimelineView(.animation)` re-renders the gradient
    /// at the display's cadence; the gradient stops are recomputed every
    /// frame from the active phase's progress, so smooth animations fall
    /// out of just shifting `animationStart`.
    @ViewBuilder
    private var revealMask: some View {
        TimelineView(.animation) { ctx in
            let p = progress(at: ctx.date)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, min(1, p - 0.08))),
                    .init(color: .clear, location: max(0, min(1, p))),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// Compute the current mask progress. Both phases share the 0…1.1
    /// scale: reveal climbs from 0, erase decays from `eraseStartProgress`.
    /// When `elapsed` is negative (mount-delay window pre-reveal) the
    /// resting state depends on the phase: pre-reveal sits at clear,
    /// pre-erase at the captured start progress.
    private func progress(at now: Date) -> CGFloat {
        let elapsed = now.timeIntervalSince(animationStart)
        switch phase {
            case .reveal:
                guard elapsed >= 0 else { return 0 }
                let raw = min(1.0, elapsed / revealDuration)
                // Ease-out cubic — sweep starts fast, settles softly.
                let eased = 1 - pow(1 - raw, 3)
                return CGFloat(eased) * 1.1
            case .erase:
                guard elapsed >= 0 else { return eraseStartProgress }
                // Erase duration is scaled by `eraseStartProgress / 1.1`
                // in `handleTextChange`, so use the same scaled denominator
                // here to keep the easing curve consistent with the
                // shorter total time.
                let scaled = eraseDuration * Double(eraseStartProgress / 1.1)
                let raw = scaled > 0 ? min(1.0, elapsed / scaled) : 1.0
                // Ease-out cubic — wipe starts fast (clearly visible
                // motion right away), trails off as it lands at 0.
                let eased = 1 - pow(1 - raw, 3)
                return eraseStartProgress * CGFloat(1 - eased)
        }
    }

    /// Soft rainbow halo behind the ticker. The blur radius extends the
    /// fill past the capsule's geometric bounds, so the glow visibly
    /// "leaks" out around the chassis without us having to add negative
    /// padding (which would fight the parent's `.frame(width:)`).
    @ViewBuilder
    private var progressGlow: some View {
        Capsule()
            .fill(progressGradient)
            .hueRotation(.degrees(hueRotation))
            .blur(radius: 20)
            .opacity(0.55)
    }

}
