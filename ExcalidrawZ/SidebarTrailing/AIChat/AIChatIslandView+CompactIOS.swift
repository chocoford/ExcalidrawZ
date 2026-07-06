//
//  AIChatIslandView+CompactIOS.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/05.
//

#if os(iOS)
import SwiftUI

extension AIChatIslandView {
    @ViewBuilder
    func compactIslandBody() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCompactingThisConversation {
                CompactingIndicatorView()
                    .transition(.opacity)
            }

            ApprovalPromptView()

            PromptInputView(
                conversationID: conversationIDBinding,
                pendingQueue: $aiChatState.pendingQueue,
                style: .compactIOS
            )
            .disabled(fileState.isAIChatConversationLoading || fileState.currentActiveFileIsInTrash)
        }
        .frame(width: islandWidth)
        .animation(
            .easeInOut(duration: 0.25),
            value: shouldShowApprovalCard
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: isCompactingThisConversation
        )
    }
}
#endif
