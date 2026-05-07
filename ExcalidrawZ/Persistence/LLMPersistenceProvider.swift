//
//  LLMPersistenceProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 2026/01/11.
//
//  Bridges LLMKit's `PersistenceProvider` protocol to the app's Core
//  Data store via `AIConversationRepository`. Two responsibilities:
//
//  1. **restoreConversations()**: Read every persisted `AIConversation`
//     row + its messages back into in-memory `LLMKit.Conversation`
//     values, called once at app launch by LLMKit.
//  2. **updateConversation(action:)**: Apply the model's mutation
//     events (insert / update message / update title / delete) to
//     Core Data so the next launch sees them.
//
//  ## Persistence model — what's stored vs reconstructed
//
//  - `Conversation.id / type / title / createdAt / lastChatAt` — stored.
//  - `Conversation.agentConfig` — **not stored**, rebuilt from
//    `ExcalidrawAgentConfig.defaultConfig()` on restore. This is
//    deliberate: this app's chat is fixed (single agent, fixed tool
//    roster), so persisting agentConfig would just lock old conversations
//    to their original tool list. Rebuilding picks up new tools added
//    in later releases. If the chat ever becomes user-selectable, this
//    is the spot to add a stored override.
//  - `ChatMessageContent.id / role / content / usage` — stored as
//    columns on `AIConversationMessage`.
//  - `ChatMessageContent.toolCalls` — stored as JSON (`toolCallsData`).
//    Required for native tool-use roundtrip: without it, a restored
//    assistant message that had pending tool calls comes back empty,
//    and the next provider request fails Anthropic's tool_use/tool_result
//    pairing check.
//  - `ChatMessageContent.toolCallId` — stored as `toolCallId` column.
//    Tool-result messages need this to resolve back to their parent
//    tool call.
//  - `ChatMessageContent.files` — **not stored** today. The chat input
//    doesn't yet emit attached files, so there's nothing to lose;
//    when image upload lands we'll add a `filesData` column with
//    external-storage Binary (base64 attachments can be MB-scale).
//

import SwiftUI
import CoreData

import LLMCore
import LLMKit

@MainActor
struct LLMPersistenceProvider: PersistenceProvider {
    var preview: Bool = false

    private var repository: AIConversationRepository {
        PersistenceController.shared.aiConversationRepository
    }

    // MARK: - Restore

    func restoreConversations() async throws -> [LLMKit.Conversation] {
        let conversations = try await repository.fetchAllConversations()

        // TaskGroup fan-out — each row's conversion is independent
        // (read-only) and runs against a fresh `newTaskContext` inside
        // the repo, so parallelism is safe. Order doesn't matter; the
        // caller (LLMKit) sorts by `lastChatAt` itself.
        let llmConversations = await withTaskGroup(of: LLMKit.Conversation?.self) { group in
            for conversation in conversations {
                group.addTask {
                    await convertToLLMKitConversation(conversation)
                }
            }

            var results: [LLMKit.Conversation] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }

        return llmConversations
    }

    // MARK: - Update

    func updateConversation(action: ConversationUpdateAction) async throws {
        switch action {
            case .insert(let conversation):
                try await insertConversation(conversation)

            case .update(let conversationID, let action):
                try await updateConversationAction(conversationID: conversationID, action: action)

            case .delete(let conversationID):
                try await repository.deleteConversation(conversationID: conversationID)
        }
    }

    // MARK: - Conversion: Core Data → LLMKit

    private func convertToLLMKitConversation(_ row: AIConversation) async -> LLMKit.Conversation? {
        // Sorted by timeStamp so the message ordering survives restore.
        // Core Data's `messages` relationship is an unordered NSSet.
        let messageSet = row.messages as? Set<AIConversationMessage> ?? []
        let sortedMessages = messageSet.sorted { ($0.timeStamp ?? Date()) < ($1.timeStamp ?? Date()) }
        let chatMessages = sortedMessages.compactMap { convertToLLMKitMessage($0) }

        return LLMKit.Conversation(
            id: row.conversationID ?? UUID().uuidString,
            type: decodeConversationType(row.type),
            // agentConfig intentionally not persisted — rebuild from the
            // app's single source of truth. See file header for why.
            agentConfig: ExcalidrawAgentConfig.defaultConfig(),
            title: row.title ?? "Untitled",
            messages: chatMessages,
            createdAt: row.createdAt ?? Date(),
            lastChatAt: row.lastChatAt ?? Date()
        )
    }

    private func convertToLLMKitMessage(_ row: AIConversationMessage) -> ChatMessage? {
        let messageType = row.messageType ?? "content"
        let messageID = row.messageID ?? UUID().uuidString

        switch messageType {
            case "content":
                let role = decodeRole(row.role)
                let usage = CreditsResult(consumed: row.usageConsumed, remains: row.usageRemains)
                let toolCalls = decodeToolCalls(row.toolCallsData)
                let content = ChatMessageContent(
                    id: messageID,
                    role: role,
                    content: row.content ?? "",
                    files: [],
                    usage: usage,
                    toolCalls: toolCalls,
                    toolCallId: row.toolCallId
                )
                return .content(content)

            case "agentStep":
                // Legacy rows from the prompt-based ReAct era. Native
                // tool-use no longer has a separate step type — we
                // surface these as plain assistant content so old
                // history stays readable. They won't have toolCalls or
                // toolCallId fields populated.
                let content = ChatMessageContent(
                    id: messageID,
                    role: .assistant,
                    content: row.content ?? "",
                    files: []
                )
                return .content(content)

            case "error":
                return .error(
                    UUID(uuidString: messageID) ?? UUID(),
                    row.content ?? "Unknown error"
                )

            default:
                return nil
        }
    }

    // MARK: - Conversion: LLMKit → Core Data

    private func insertConversation(_ conversation: LLMKit.Conversation) async throws {
        // `Conversation.type` rawValue is canonical for normal/temporary;
        // for `.custom(label)` it's just the label. We persist that
        // string verbatim and reverse it in `decodeConversationType`.
        let conversationObjectID = try await repository.createConversation(
            conversationID: conversation.id,
            title: conversation.title,
            type: conversation.type.rawValue,
            // File association isn't pushed through LLMKit's
            // Conversation type; it's set by app-level wiring elsewhere
            // when a conversation is bound to a canvas file.
            fileObjectID: nil
        )

        for message in conversation.messages {
            try await createMessageFromChatMessage(
                message,
                conversationObjectID: conversationObjectID
            )
        }
    }

    private func updateConversationAction(
        conversationID: String,
        action: ChatMessageUpdateAction
    ) async throws {
        guard let conversationObjectID = try await repository.findConversationObjectID(conversationID: conversationID) else {
            throw AppError.fileError(.notFound)
        }

        switch action {
            case .updateTitle(let title):
                try await repository.updateTitle(conversationObjectID: conversationObjectID, title: title)

            case .insert(let messages):
                for message in messages {
                    try await createMessageFromChatMessage(
                        message,
                        conversationObjectID: conversationObjectID
                    )
                }

            case .update(let message):
                try await updateMessageFromChatMessage(message)

            case .delete(let messageIDs):
                try await repository.deleteMessages(messageIDs: messageIDs)
        }
    }

    private func createMessageFromChatMessage(
        _ chatMessage: ChatMessage,
        conversationObjectID: NSManagedObjectID
    ) async throws {
        switch chatMessage {
            case .content(let message):
                let messageObjectID = try await repository.createMessage(
                    messageID: message.id,
                    messageType: "content",
                    content: message.content ?? "",
                    role: message.role.rawValue,
                    toolCallsData: encodeToolCalls(message.toolCalls),
                    toolCallId: message.toolCallId,
                    conversationObjectID: conversationObjectID
                )

                if let usage = message.usage {
                    try await repository.updateMessage(
                        messageObjectID: messageObjectID,
                        usageConsumed: usage.consumed,
                        usageRemains: usage.remains
                    )
                }

            case .error(let id, let errorMessage):
                _ = try await repository.createMessage(
                    messageID: id.uuidString,
                    messageType: "error",
                    content: errorMessage,
                    role: "system",
                    conversationObjectID: conversationObjectID
                )

            case .loading:
                // Loading is a transient UI state — not persisted.
                break
        }
    }

    private func updateMessageFromChatMessage(_ chatMessage: ChatMessage) async throws {
        switch chatMessage {
            case .content(let content):
                guard let messageObjectID = try await repository.findMessageObjectID(messageID: content.id) else {
                    return
                }

                // For an .update event we patch every persisted field
                // so the row reflects the latest model output. Tool
                // calls in particular: a streaming assistant message
                // accumulates tool calls late in the stream, and the
                // .update event is what flushes them — if we skipped
                // them here, only the .insert path would carry them
                // and a re-emitted update could effectively drop them.
                //
                // `clearToolCalls` is keyed on the *encoded* result
                // being nil rather than on `content.toolCalls == nil`,
                // so that an explicit empty array (`[]`, which the
                // model can transiently emit) wipes any previously
                // persisted calls rather than leaving stale data.
                let encodedToolCalls = encodeToolCalls(content.toolCalls)
                try await repository.updateMessage(
                    messageObjectID: messageObjectID,
                    content: content.content,
                    usageConsumed: content.usage?.consumed,
                    usageRemains: content.usage?.remains,
                    toolCallsData: encodedToolCalls,
                    clearToolCalls: encodedToolCalls == nil,
                    toolCallId: content.toolCallId,
                    clearToolCallId: content.toolCallId == nil
                )

            case .error(let id, let errorMessage):
                guard let messageObjectID = try await repository.findMessageObjectID(messageID: id.uuidString) else {
                    return
                }
                try await repository.updateMessage(
                    messageObjectID: messageObjectID,
                    content: errorMessage
                )

            case .loading:
                break
        }
    }

    // MARK: - Codecs

    /// Map persisted role string back to the typed enum. Falls back to
    /// `.assistant` for unknown values so legacy rows (rare, from app
    /// versions before all five roles were possible) don't drop out of
    /// the conversation. The previous implementation only recognized
    /// "user" and silently coerced everything else to `.assistant` —
    /// which broke tool-result roundtrip because `.tool` rows came back
    /// as `.assistant` and the next provider request lost the
    /// tool_use ↔ tool_result pairing.
    private func decodeRole(_ raw: String?) -> ChatMessageContent.Role {
        guard let raw, let role = ChatMessageContent.Role(rawValue: raw) else {
            return .assistant
        }
        return role
    }

    /// `Conversation.ConversationTpye` rawValue is "normal" / "temporary"
    /// for the namesake cases and the label string for `.custom(label)`.
    /// On decode we reverse that mapping: fixed strings → fixed cases,
    /// anything else → `.custom(rawValue)`. `nil` falls back to
    /// `.custom("Chat")` to match the historical default.
    private func decodeConversationType(_ raw: String?) -> LLMKit.Conversation.ConversationTpye {
        guard let raw else { return .custom("Chat") }
        switch raw {
            case "normal":    return .normal
            case "temporary": return .temporary
            default:          return .custom(raw)
        }
    }

    private func encodeToolCalls(_ toolCalls: [ToolCall]?) -> Data? {
        guard let toolCalls, !toolCalls.isEmpty else { return nil }
        return try? JSONEncoder().encode(toolCalls)
    }

    private func decodeToolCalls(_ data: Data?) -> [ToolCall]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([ToolCall].self, from: data)
    }
}
