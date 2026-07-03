//
//  CompactAIChatEditorOverlays.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/03.
//

#if os(iOS)
import SwiftUI
import UIKit
import LLMCore
import LLMKit

enum CompactAIChatOverlayMetrics {
    static let horizontalPadding: CGFloat = 12
    static let toolbarBottomPadding: CGFloat = 12
    static let toolbarControlLength: CGFloat = 80
    static let tickerHeight: CGFloat = 48
    static let tickerFullscreenButtonLength: CGFloat = 38
    static let tickerAppearDelay: Duration = .milliseconds(140)
    static let tickerCollapseDuration: Duration = .milliseconds(360)
}

struct CompactAIChatEditorOverlays: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var isCompactIOS: Bool {
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
    }

    private var canShowCompactAIChatControls: Bool {
        isCompactIOS &&
            layoutState.isCompactAIChatToolbarPresented &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var conversation: Conversation? {
        llmState.conversations.value?
            .first { $0.id == fileState.aiChatConversationID }
    }

    private var conversationMessageCount: Int {
        conversation?.messages.count ?? 0
    }

    private var draftState: AIChatPromptDraftState {
        aiChatState.promptDraftState(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    private var replyTickerIsActive: Bool {
        compactAIChatIsGenerating ||
            layoutState.isCompactAIChatReplyTickerVisible ||
            layoutState.isCompactAIChatReplyStartPending
    }

    private var compactAIChatIsGenerating: Bool {
        guard let conversationID = fileState.aiChatConversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if canShowCompactAIChatControls {
                CompactAIChatAccessoryStack {
                    CompactAIChatApprovalPrompt()
                        .ignoredWhenCollapsed()

                    CompactAIChatDraftAttachmentBar(
                        draftState: draftState,
                        replyTickerIsActive: replyTickerIsActive
                    ) {
                        layoutState.enterCompactAIChatInputEditing()
                    }
                    .ignoredWhenCollapsed()

                    CompactAIChatProposalAnchor(
                        draftState: draftState,
                        replyTickerIsActive: replyTickerIsActive
                    )
                    .ignoredWhenCollapsed()

                    CompactAIChatReplyTicker(
                        conversationID: fileState.aiChatConversationID,
                        isGenerating: compactAIChatIsGenerating
                    )
                    .ignoredWhenCollapsed()
                }
                .modifier(AIChatIslandProposalModifier(
                    conversationID: fileState.aiChatConversationID,
                    conversation: conversation,
                    conversationMessageCount: conversationMessageCount,
                    islandWidth: nil
                ))
            }

            CompactAIChatInputOverlay()
        }
    }
}

private struct CompactAIChatAccessoryStack<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        CollapsibleSpacingVStack(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CompactAIChatOverlayMetrics.horizontalPadding)
        .padding(.bottom, CompactAIChatOverlayMetrics.toolbarBottomPadding)
        .safeAreaPadding(.bottom)
    }
}

private struct CompactAIChatApprovalPrompt: View {
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var llmState: LLMStateObject

    var body: some View {
        if !layoutState.isCompactAIChatFullChatPresented {
            ApprovalPromptView(autofocusDenyReason: false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: llmState.pendingApprovalRequest != nil)
        }
    }
}

private struct CompactAIChatDraftAttachmentBar: View {
    @EnvironmentObject private var layoutState: LayoutState

    @ObservedObject var draftState: AIChatPromptDraftState
    let replyTickerIsActive: Bool
    let onTap: () -> Void

    var body: some View {
        if !layoutState.isCompactAIChatInputEditing,
           !replyTickerIsActive,
           !draftState.images.isEmpty {
            HStack(spacing: 0) {
                CompactAIChatDraftAttachmentStrip(draftState: draftState, onTap: onTap)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.smooth(duration: 0.18), value: draftState.images.count)
        }
    }
}

private struct CompactAIChatProposalAnchor: View {
    @EnvironmentObject private var layoutState: LayoutState

    @ObservedObject var draftState: AIChatPromptDraftState
    let replyTickerIsActive: Bool

    var body: some View {
        if !layoutState.isCompactAIChatInputEditing,
           !replyTickerIsActive,
           draftState.images.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: CompactAIChatOverlayMetrics.tickerHeight)
                .allowsHitTesting(false)
        }
    }
}

private struct CompactAIChatDraftAttachmentStrip: View {
    @ObservedObject var draftState: AIChatPromptDraftState

    let onTap: () -> Void

    private var visibleImages: [PendingPastedImage] {
        Array(draftState.images.prefix(4))
    }

    private var remainingCount: Int {
        max(0, draftState.images.count - visibleImages.count)
    }

    var body: some View {
        if !draftState.images.isEmpty {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    ForEach(visibleImages) { image in
                        CompactAIChatDraftAttachmentThumbnail(image: image)
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.thinMaterial)
                            }
                    }
                }
                .padding(6)
                .background {
                    attachmentStripBackground
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Attached images")
        }
    }

    @ViewBuilder
    private var attachmentStripBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
        }
    }
}

private struct CompactAIChatDraftAttachmentThumbnail: View {
    let image: PendingPastedImage

    var body: some View {
        Image(uiImage: image.image)
            .resizable()
            .scaledToFill()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}
#endif
