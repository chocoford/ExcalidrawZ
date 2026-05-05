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
import MarkdownUI
import SFSafeSymbols
import ChocofordUI

struct AIChatIslandView: View {
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var llmState: LLMStateObject

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

    private let islandWidth: CGFloat = 360
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

    private var streamingState: LLMStreamingStateObject? {
        guard let id = fileState.aiChatConversationID else { return nil }
        return llmState.streamingStore.streamIfExists(for: id)
            as? LLMStreamingStateObject
    }

    /// Show the streaming preview only while the assistant is actively
    /// generating *and* has produced enough text to be meaningful — same
    /// threshold as the inspector view, so the user doesn't see "OK!" flash
    /// here either.
    private var visibleStreamingText: String? {
        guard let stream = streamingState,
              !stream.isFinished else { return nil }
        let text = stream.content
        guard SmoothStreamingText.isMeaningfulLiveSnippet(text) else { return nil }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            
            if let text = visibleStreamingText {
                streamingPreview(text)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PromptInputView(conversationID: conversationIDBinding)
        }
        .padding(16)
        .frame(width: islandWidth)
        .background {
            islandBackground
            // Drag lives on the header so trackpad gestures inside the input or
            // the streaming preview don't fight with it.
                .contentShape(Rectangle())
                .gesture(dragGesture)
        }
        .readHeight($measuredHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .offset(
            x: layoutState.aiChatIslandOffset.width + dragDelta.width,
            y: layoutState.aiChatIslandOffset.height + dragDelta.height
        )
        .animation(.easeInOut(duration: 0.25), value: visibleStreamingText != nil)
        // Window resize / split changes shrink `canvasSize` and may strand
        // the island outside the new bounds. Clamp immediately (no 1 s
        // delay) — there's no drag in flight to wait for.
        .onChange(of: canvasSize, debounce: 1) { _ in
            snapBackTask?.cancel()
            snapBackIfOutOfBounds()
        }
    }

    // MARK: - Header / drag handle

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 4) {
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("AI Chat")
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
            .buttonStyle(.borderless)
            .help("Dock back to inspector")
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
            Markdown(text)
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
    private var islandBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 24)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        }
    }
}
