//
//  CompactAIChatInputOverlay.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

#if os(iOS)
import SwiftUI
import ChocofordUI
import UIKit
import LLMCore
import LLMKit
import SFSafeSymbols

struct CompactAIChatInputOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardAnimationDuration: TimeInterval = 0.25
    @State private var keyboardPresentationStarted = false

    private var isCompactIOS: Bool {
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
    }

    private var isVisible: Bool {
        isCompactIOS &&
        layoutState.isCompactAIChatToolbarPresented &&
        layoutState.isCompactAIChatInputEditing &&
        AIChatAvailability.isAvailable &&
        aiChatPreferences.isAIEnabled &&
        !fileState.currentActiveFileIsInTrash
    }

    private var conversationIDBinding: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }

    var body: some View {
        if isVisible {
            PromptInputView(
                conversationID: conversationIDBinding,
                pendingQueue: $aiChatState.pendingQueue,
                style: .compactIOSIsland,
                focusOnAppear: true,
                dismissKeyboardOnSuccessfulSubmit: true,
                onSuccessfulSubmit: {
                    guard layoutState.isCompactAIChatToolbarPresented else { return }
                    withAnimation(.smooth(duration: 0.18)) {
                        layoutState.isCompactAIChatReplyTickerVisible = true
                        layoutState.isCompactAIChatReplyStartPending = true
                    }
                }
            )
            .disabled(
                llmState.pendingApprovalRequest != nil ||
                fileState.isAIChatConversationLoading ||
                fileState.currentActiveFileIsInTrash
            )
            .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
            .padding(.bottom, bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: keyboardAnimationDuration), value: keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                keyboardPresentationStarted = true
                updateKeyboardHeight(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardHeight(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardHeight(notification, isHiding: true)
            }
        }
    }

    private var bottomPadding: CGFloat {
        keyboardHeight > 0 ? keyboardHeight + 8 : CompactAIChatOverlayMetrics.toolbarBottomPadding
    }

    private func updateKeyboardHeight(_ notification: Notification, isHiding: Bool = false) {
        if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            keyboardAnimationDuration = duration
        }

        if isHiding {
            let shouldExitEditing = keyboardPresentationStarted || keyboardHeight > 0
            keyboardHeight = 0
            keyboardPresentationStarted = false
            guard !layoutState.isCompactAIChatAttachmentPickerPresented else {
                return
            }
            guard shouldExitEditing else { return }
            layoutState.exitCompactAIChatInputEditing()
            return
        }

        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            keyboardHeight = 0
            return
        }

        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? UIScreen.main.bounds.height
        let nextKeyboardHeight = max(0, screenHeight - frame.minY)
        if nextKeyboardHeight > 0 {
            keyboardPresentationStarted = true
        }
        keyboardHeight = nextKeyboardHeight
    }
}

struct CompactAIChatReplyTicker: View {
    let conversationID: String?
    let isGenerating: Bool

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
    @State private var renderedReplyText: String?
    @State private var isTickerPresented = false
    @State private var isTickerCollapsing = false
    @State private var tickerPresentationTask: Task<Void, Never>?

    private var isStartPending: Bool {
        layoutState.isCompactAIChatReplyStartPending
    }

    private var shouldShowTicker: Bool {
        !layoutState.isCompactAIChatInputEditing &&
        (isGenerating ||
         layoutState.isCompactAIChatReplyTickerVisible ||
         isStartPending)
    }

    private var leadingPadding: CGFloat {
        CompactAIChatOverlayMetrics.toolbarControlLength
    }

    private var trailingPadding: CGFloat {
        shouldReserveStopButtonSpace ? CompactAIChatOverlayMetrics.toolbarControlLength : 0
    }

    private var shouldReserveStopButtonSpace: Bool {
        isGenerating || isStartPending
    }

    private var pendingReplyFailureID: UUID? {
        guard isStartPending,
              !isGenerating,
              let transientError = aiChatState.transientError
        else {
            return nil
        }

        if let conversationID,
           transientError.conversationID != conversationID {
            return nil
        }

        return transientError.id
    }

    var body: some View {
        if shouldShowTicker {
            tickerHost
                .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private var tickerHost: some View {
        AIChatReplyTickerHost(onReplyTextChange: updateReplyTickerVisibility) { replyText in
            let text = renderedReplyText ?? replyText
            if text != nil || isStartPending {
                CompactAIChatReplyTickerCapsule(
                    text: text,
                    isPending: isStartPending
                )
                .scaleEffect(
                    x: tickerScaleX,
                    y: tickerScaleY,
                    anchor: tickerScaleAnchor
                )
                .opacity(isTickerPresented || !isTickerCollapsing ? 1 : 0)
                .padding(.leading, leadingPadding)
                .padding(.trailing, trailingPadding)
                .animation(.smooth(duration: 0.24), value: shouldReserveStopButtonSpace)
                .allowsHitTesting(isTickerPresented)
            }
        }
        .watch(value: pendingReplyFailureID) { _, failureID in
            guard failureID != nil else { return }
            dismissPendingReplyTicker()
        }
    }

    private func updateReplyTickerVisibility(_ replyText: String?) {
        Task { @MainActor in
            handleReplyTickerVisibility(replyText)
        }
    }

    @MainActor
    private func handleReplyTickerVisibility(_ replyText: String?) {
        tickerPresentationTask?.cancel()

        if let replyText {
            isTickerCollapsing = false
            renderedReplyText = replyText
            if !layoutState.isCompactAIChatReplyTickerVisible {
                withAnimation(.smooth(duration: 0.18)) {
                    layoutState.isCompactAIChatReplyTickerVisible = true
                }
            }
            layoutState.isCompactAIChatReplyStartPending = false

            guard !isTickerPresented else { return }
            tickerPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerAppearDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    isTickerPresented = true
                }
            }
            return
        }

        if isStartPending {
            if pendingReplyFailureID != nil {
                dismissPendingReplyTicker()
                return
            }
            isTickerCollapsing = false
            guard !isTickerPresented else { return }
            tickerPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerAppearDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    isTickerPresented = true
                }
            }
            return
        }

        guard renderedReplyText != nil || isTickerPresented else { return }

        withAnimation(.bouncy(duration: 0.36, extraBounce: 0.18)) {
            isTickerCollapsing = true
            isTickerPresented = false
        }
        tickerPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: CompactAIChatOverlayMetrics.tickerCollapseDuration)
            guard !Task.isCancelled else { return }
            renderedReplyText = nil
            withAnimation(.smooth(duration: 0.2)) {
                layoutState.isCompactAIChatReplyTickerVisible = false
                layoutState.isCompactAIChatReplyStartPending = false
            }
        }
    }

    @MainActor
    private func dismissPendingReplyTicker() {
        tickerPresentationTask?.cancel()
        renderedReplyText = nil
        isTickerCollapsing = false
        withAnimation(.smooth(duration: 0.18)) {
            isTickerPresented = false
            layoutState.isCompactAIChatReplyTickerVisible = false
            layoutState.isCompactAIChatReplyStartPending = false
        }
    }

    private var tickerScaleX: CGFloat {
        guard !isTickerPresented else { return 1 }
        return isTickerCollapsing ? 0.18 : 0.01
    }

    private var tickerScaleY: CGFloat {
        guard !isTickerPresented else { return 1 }
        return isTickerCollapsing ? 0.18 : 1
    }

    private var tickerScaleAnchor: UnitPoint {
        isTickerCollapsing ? .center : .leading
    }
}

private struct CompactAIChatReplyTickerCapsule: View {
    let text: String?
    let isPending: Bool

    var body: some View {
        ReplyTickerView(text: text ?? "")
            .transition(.opacity)
            .frame(maxWidth: .infinity)
            .frame(height: CompactAIChatOverlayMetrics.tickerHeight)
            .background {
                tickerBackground
                if text == nil, isPending {
                    tickerGlow
                }
            }
            .animation(.smooth(duration: 0.18), value: text != nil)
            .animation(.smooth(duration: 0.18), value: isPending)
    }

    @ViewBuilder
    private var tickerBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var tickerGlow: some View {
        Capsule()
            .fill(AIAppearancePalette.thinkingGradient)
            .blur(radius: 20)
            .opacity(0.55)
    }
}
#endif
