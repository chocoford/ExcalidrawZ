//
//  AIChatIslandProposal.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/02.
//

import SwiftUI
import LLMKit
import LLMCore
import ChocofordUI

struct AIChatIslandProposal: Equatable {
    let messageID: String
    let artifact: AIProposalArtifact
    let previewFile: ChatMessageContent.File?
}

struct AIChatIslandProposalModifier: ViewModifier {
    let conversationID: String?
    let conversation: Conversation?
    let conversationMessageCount: Int
    let islandWidth: CGFloat?
    let proposalHorizontalPadding: CGFloat

    init(
        conversationID: String?,
        conversation: Conversation?,
        conversationMessageCount: Int,
        islandWidth: CGFloat?,
        proposalHorizontalPadding: CGFloat = 0
    ) {
        self.conversationID = conversationID
        self.conversation = conversation
        self.conversationMessageCount = conversationMessageCount
        self.islandWidth = islandWidth
        self.proposalHorizontalPadding = proposalHorizontalPadding
    }

    /// Island mode pins only proposals created while this island is alive.
    /// We seed from the current conversation on appear, then store newly
    /// encountered proposals in state instead of recomputing from history.
    @State private var activeProposal: AIChatIslandProposal?
    @State private var isProposalVisible = false
    @State private var proposalTrackingConversationID: String?
    @State private var hasSeededProposalBaseline = false
    @State private var lastObservedProposalMessageID: String?
    @State private var lastObservedUserMessageID: String?

    private var latestProposalMessage: AIChatIslandProposal? {
        guard let messages = conversation?.messages else { return nil }

        for message in messages.reversed() {
            guard case .content(let content) = message,
                  content.role == .tool,
                  let artifact = AIProposalArtifact.parse(from: content) else {
                continue
            }

            return AIChatIslandProposal(
                messageID: content.id,
                artifact: artifact,
                previewFile: firstImageFile(in: content)
            )
        }

        return nil
    }

    private var latestProposalMessageID: String? {
        latestProposalMessage?.messageID
    }

    private var latestUserMessageID: String? {
        conversation?.messages.last { message in
            guard case .content(let content) = message else { return false }
            return content.role == .user
        }?.id
    }

    func body(content: Content) -> some View {
        CollapsibleSpacingVStack(spacing: 10) {
            AnimatedPresence(
                value: isProposalVisible ? activeProposal : nil,
                contentTransition: .deferredOpacity
            ) { proposal in
                proposalCard(proposal)
            }
            .ignoredWhenCollapsed()

            content
        }
        .animation(.easeInOut(duration: 0.22), value: activeProposal?.messageID)
        .onAppear {
            syncUserMessageTracking()
            syncProposalTracking()
        }
        .watch(value: conversationID) { _, _ in
            resetProposalTrackingForCurrentConversation()
            syncUserMessageTracking()
            syncProposalTracking()
        }
        .watch(value: conversationMessageCount) { _, _ in
            syncProposalTracking()
        }
        .watch(value: latestProposalMessageID) { _, _ in
            syncProposalTracking()
        }
        .watch(value: latestUserMessageID) { _, _ in
            syncUserMessageTracking()
        }
    }

    private func firstImageFile(in content: ChatMessageContent) -> ChatMessageContent.File? {
        (content.files ?? []).first { file in
            switch file {
                case .base64EncodedImage, .image:
                    return true
            }
        }
    }

    private func resetProposalTrackingForCurrentConversation() {
        proposalTrackingConversationID = conversationID
        activeProposal = nil
        isProposalVisible = false
        lastObservedProposalMessageID = nil
        lastObservedUserMessageID = nil
        hasSeededProposalBaseline = false
    }

    private func syncUserMessageTracking() {
        if proposalTrackingConversationID != conversationID {
            resetProposalTrackingForCurrentConversation()
        }

        let userMessageID = latestUserMessageID
        defer { lastObservedUserMessageID = userMessageID }

        guard userMessageID != lastObservedUserMessageID,
              lastObservedUserMessageID != nil,
              isProposalVisible else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isProposalVisible = false
        }
    }

    private func syncProposalTracking() {
        if proposalTrackingConversationID != conversationID {
            resetProposalTrackingForCurrentConversation()
        }

        guard conversation != nil else { return }

        guard hasSeededProposalBaseline else {
            lastObservedProposalMessageID = latestProposalMessageID
            hasSeededProposalBaseline = true
            return
        }

        guard let proposal = latestProposalMessage else {
            lastObservedProposalMessageID = nil
            activeProposal = nil
            isProposalVisible = false
            return
        }

        guard proposal.messageID != lastObservedProposalMessageID else { return }
        lastObservedProposalMessageID = proposal.messageID

        withAnimation(.easeInOut(duration: 0.22)) {
            activeProposal = proposal
            isProposalVisible = true
        }
    }

    @ViewBuilder
    private func proposalCard(_ proposal: AIChatIslandProposal) -> some View {
        AIProposalToolResultCard(
            artifact: proposal.artifact,
            previewFile: proposal.previewFile,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isProposalVisible = false
                }
            }
        )
        .id(proposal.messageID)
        .modifier(AIProposalCardWidthModifier(
            width: islandWidth,
            horizontalPadding: proposalHorizontalPadding
        ))
    }
}

private struct AIProposalCardWidthModifier: ViewModifier {
    let width: CGFloat?
    let horizontalPadding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width)
        } else {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
        }
    }
}
