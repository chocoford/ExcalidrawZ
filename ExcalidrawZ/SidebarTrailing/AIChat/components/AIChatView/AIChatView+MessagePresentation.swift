//
//  AIChatView+MessagePresentation.swift
//  ExcalidrawZ
//

import LLMCore
import LLMKit

extension AIChatView {
    func containsErrorMessage(
        in groups: [MessageGroup],
        matching message: String
    ) -> Bool {
        groups.contains { group in
            guard case .error(_, let existingMessage) = group else { return false }
            return existingMessage == message
        }
    }

    func streamingAssistantMessageIDs(
        in groups: [MessageGroup],
        conversationID: String?
    ) -> Set<String> {
        guard let conversationID else { return [] }
        guard !aiChatState.isGenerationCancelled(conversationID: conversationID) else {
            return []
        }
        var result: Set<String> = []
        for group in groups {
            guard case .assistantRound(_, let messages) = group else { continue }
            for message in messages {
                guard case .content(let content) = message,
                      content.role == .assistant
                else {
                    continue
                }
                if llmState.isStreaming(messageID: content.id, in: conversationID) {
                    result.insert(content.id)
                }
            }
        }
        return result
    }

    func messageGroupPresentationSignature(
        _ group: MessageGroup,
        streamingMessageIDs: Set<String>
    ) -> String {
        switch group {
            case .user(let content):
                return [
                    "user",
                    content.id,
                    "\(content.content?.count ?? 0)",
                    "files:\(content.files?.count ?? 0)"
                ].joined(separator: ":")
            case .assistantRound(let id, let messages):
                let messageSignature = messages.map { message -> String in
                    switch message {
                        case .content(let content):
                            return [
                                content.id,
                                String(describing: content.role),
                                messageContentPresentationSignature(
                                    content,
                                    streamingMessageIDs: streamingMessageIDs
                                ),
                                toolCallPresentationSignature(
                                    content,
                                    streamingMessageIDs: streamingMessageIDs
                                ),
                                "toolCallID:\(content.toolCallId ?? "nil")",
                                "files:\(content.files?.count ?? 0)"
                            ].joined(separator: ":")
                        case .loading(let id):
                            return "loading:\(id.uuidString)"
                        case .error(let id, let message):
                            return "error:\(id.uuidString):\(message)"
                    }
                }.joined(separator: "|")
                return "assistantRound:\(id)::\(messageSignature)"
            case .loading(let id):
                return "loading:\(id.uuidString)"
            case .error(let id, let message):
                return "error:\(id.uuidString):\(message)"
            case .compactSummary(let content):
                return [
                    "compactSummary",
                    content.id,
                    "\(content.content?.count ?? 0)"
                ].joined(separator: ":")
        }
    }

    func messageContentPresentationSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard content.role == .assistant,
              streamingMessageIDs.contains(content.id),
              shouldHideStreamingAssistantContent(content)
        else {
            return "content:\(content.content?.count ?? 0)"
        }
        return "hidden-streaming-content"
    }

    func toolCallPresentationSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard let calls = content.toolCalls else { return "toolCalls:nil" }
        let isHiddenStreamingAssistant = content.role == .assistant
        && streamingMessageIDs.contains(content.id)
        let callSignature = calls.map { call in
            if isHiddenStreamingAssistant {
                return "\(call.id):\(call.name):hidden-streaming-args"
            }
            return "\(call.id):\(call.name):args:\(call.arguments.count)"
        }.joined(separator: ",")
        return "toolCalls:\(callSignature)"
    }

    func shouldHideStreamingAssistantContent(_ content: ChatMessageContent) -> Bool {
        let hasFinalCall = content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
        if hasFinalCall { return true }
        let text = displayText(of: content)
        guard !text.isEmpty else { return false }
        let hasToolCallsStarted = content.toolCalls != nil
        return !hasToolCallsStarted
    }

    func displayText(of content: ChatMessageContent) -> String {
        if let finalCall = content.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return content.content ?? ""
    }
}
