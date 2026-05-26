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
//  - `Conversation.agentConfig` — rebuilt from
//    `ExcalidrawAgentConfig.defaultConfig(...)` on restore. The server
//    agent id stays app-owned, while the current conversation's tool
//    roster is persisted as `AIConversation.toolsData` so model-specific
//    capability filters survive relaunch.
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
//  - `ChatMessageContent.files` — stored as a JSON `[PersistedFile]`
//    index in the `filesData` column. The actual bytes live under
//    `AIChatAttachments/<conversationID>/<UUID>.<ext>` in the managed
//    file storage tree (iCloud-Drive-synced) and are written /
//    resolved through `AIChatAttachmentRepository`. Provider never
//    touches disk directly.
//  - `ChatMessageContent.isCompactedOut / .isCompactSummary` — stored
//    as boolean columns. LLMKit's `compactConversation` flips
//    `isCompactedOut` on older rows and inserts a fresh
//    `isCompactSummary` row; both must round-trip so a re-launched
//    chat picks up where the user left off (older messages stay
//    dimmed, the summary card stays as the LLM's actual context).
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

    private var attachmentRepository: AIChatAttachmentRepository {
        PersistenceController.shared.aiChatAttachmentRepository
    }

    // MARK: - Restore

    func restoreConversations() async throws -> [LLMKit.Conversation] {
        // Use the snapshot path: the repo extracts all primitives +
        // sorted messages inside its `context.perform` block, so we
        // never touch a `NSManagedObject` from off-queue. Touching
        // the `messages` relationship after the perform block exits
        // returned an empty set, which used to make every restored
        // conversation look like it had no history.
        let snapshots = try await repository.fetchAllConversationSnapshots()

        // TaskGroup fan-out — each snapshot's conversion is
        // independent and may do async work (attachment resolution),
        // so parallelism is fine. Order doesn't matter; the caller
        // (LLMKit) sorts by `lastChatAt` itself.
        let llmConversations = await withTaskGroup(of: LLMKit.Conversation?.self) { group in
            for snapshot in snapshots {
                group.addTask {
                    await convertToLLMKitConversation(snapshot)
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

    private func convertToLLMKitConversation(_ snapshot: AIConversationSnapshot) async -> LLMKit.Conversation? {
        var chatMessages: [ChatMessage] = []
        for messageSnapshot in snapshot.messages {
            guard let msg = await convertToLLMKitMessage(messageSnapshot) else { continue }
            chatMessages.append(msg)
        }

        return LLMKit.Conversation(
            id: snapshot.conversationID ?? UUID().uuidString,
            type: decodeConversationType(snapshot.type),
            agentConfig: ExcalidrawAgentConfig.defaultConfig(
                tools: decodeToolNames(snapshot.toolsData)
            ),
            title: snapshot.title ?? "Untitled",
            messages: chatMessages,
            createdAt: snapshot.createdAt ?? Date(),
            lastChatAt: snapshot.lastChatAt ?? Date()
        )
    }

    private func convertToLLMKitMessage(_ snapshot: AIConversationMessageSnapshot) async -> ChatMessage? {
        let messageType = snapshot.messageType ?? "content"
        let messageID = snapshot.messageID ?? UUID().uuidString
        let contentText = snapshot.content ?? ""

        switch messageType {
            case "content":
                let role = decodeRole(snapshot.role)
                let usage = CreditsResult(
                    consumed: snapshot.usageConsumed,
                    remains: snapshot.usageRemains
                )
                let toolCalls = decodeToolCalls(snapshot.toolCallsData)
                let files = await resolveFiles(from: snapshot.filesData)
                let content = ChatMessageContent(
                    id: messageID,
                    role: role,
                    content: contentText,
                    files: files,
                    usage: usage,
                    toolCalls: toolCalls,
                    toolCallId: snapshot.toolCallId,
                    isCompactedOut: snapshot.isCompactedOut,
                    isCompactSummary: snapshot.isCompactSummary
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
                    content: contentText,
                    files: []
                )
                return .content(content)

            case "error":
                return .error(
                    UUID(uuidString: messageID) ?? UUID(),
                    contentText.isEmpty ? "Unknown error" : contentText
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
            toolsData: ExcalidrawAgentConfig.encodeToolNames(conversation.agentConfig.tools)
        )

        for message in conversation.messages {
            try await createMessageFromChatMessage(
                message,
                conversationID: conversation.id,
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
                        conversationID: conversationID,
                        conversationObjectID: conversationObjectID
                    )
                }

            case .update(let message):
                try await updateMessageFromChatMessage(message, conversationID: conversationID)

            case .delete(let messageIDs):
                try await repository.deleteMessages(messageIDs: messageIDs)
        }
    }

    private func createMessageFromChatMessage(
        _ chatMessage: ChatMessage,
        conversationID: String,
        conversationObjectID: NSManagedObjectID
    ) async throws {
        switch chatMessage {
            case .content(let message):
                let filesData = await persistFiles(
                    message.files,
                    conversationID: conversationID
                )
                let messageObjectID = try await repository.createMessage(
                    messageID: message.id,
                    messageType: "content",
                    content: message.content ?? "",
                    role: message.role.rawValue,
                    toolCallsData: encodeToolCalls(message.toolCalls),
                    toolCallId: message.toolCallId,
                    filesData: filesData,
                    isCompactedOut: message.isCompactedOut,
                    isCompactSummary: message.isCompactSummary,
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

    private func updateMessageFromChatMessage(
        _ chatMessage: ChatMessage,
        conversationID: String
    ) async throws {
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
                // `clearToolCalls` / `clearFiles` are keyed on the
                // *encoded* result being nil rather than on the input
                // being nil, so that an explicit empty array (`[]`,
                // which the model can transiently emit) wipes any
                // previously persisted data rather than leaving it
                // stale.
                let encodedToolCalls = encodeToolCalls(content.toolCalls)
                let encodedFiles = await persistFiles(content.files, conversationID: conversationID)
                try await repository.updateMessage(
                    messageObjectID: messageObjectID,
                    content: content.content,
                    usageConsumed: content.usage?.consumed,
                    usageRemains: content.usage?.remains,
                    toolCallsData: encodedToolCalls,
                    clearToolCalls: encodedToolCalls == nil,
                    toolCallId: content.toolCallId,
                    clearToolCallId: content.toolCallId == nil,
                    filesData: encodedFiles,
                    clearFiles: encodedFiles == nil,
                    // Always write the latest compact flags. LLMKit's
                    // `compactConversation` flips `isCompactedOut` on
                    // older rows and emits `.update` events; without
                    // this the flag would never reach the store.
                    isCompactedOut: content.isCompactedOut,
                    isCompactSummary: content.isCompactSummary
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
            case "normal":    return .regular
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

    private func decodeToolNames(_ data: Data?) -> [String]? {
        ExcalidrawAgentConfig.decodeToolNames(data)
    }

    // MARK: - Files (attachments)

    /// Persist every `ChatMessageContent.File` for a message and
    /// return the JSON blob ready to drop into `filesData`. Each file
    /// goes through `AIChatAttachmentRepository.persist`, which writes
    /// bytes (for base64 / local-URL forms) and produces a
    /// `PersistedFile` record we can later resolve back. Failures are
    /// logged inside the repo and dropped — we keep the message even
    /// if one attachment can't be saved.
    private func persistFiles(
        _ files: [ChatMessageContent.File]?,
        conversationID: String
    ) async -> Data? {
        guard let files, !files.isEmpty else { return nil }
        var persisted: [PersistedFile] = []
        persisted.reserveCapacity(files.count)
        for file in files {
            do {
                let record = try await attachmentRepository.persist(
                    file,
                    conversationID: conversationID
                )
                persisted.append(record)
            } catch {
                // Best-effort: skip the failing attachment, keep the
                // others. The message itself shouldn't be blocked by a
                // single bad image.
                continue
            }
        }
        guard !persisted.isEmpty else { return nil }
        return try? JSONEncoder().encode(persisted)
    }

    /// Reverse: decode a `filesData` blob and resolve each record back
    /// to a usable `ChatMessageContent.File`. Records that can't be
    /// rebuilt (malformed JSON, missing local file with no fallback)
    /// are silently dropped — UI sees the surviving subset.
    private func resolveFiles(from data: Data?) async -> [ChatMessageContent.File] {
        let records = decodePersistedFiles(from: data)
        guard !records.isEmpty else { return [] }
        var out: [ChatMessageContent.File] = []
        out.reserveCapacity(records.count)
        for record in records {
            if let file = await attachmentRepository.resolve(record) {
                out.append(file)
            }
        }
        return out
    }

    /// Shared decode helper: used both during restore and during the
    /// pre-delete sweep that needs to know which files belong to a
    /// conversation about to be removed. Returns `[]` for nil/empty/
    /// malformed input — callers don't get to distinguish "no files"
    /// from "couldn't decode", which matches our drop-on-error policy
    /// for all file roundtrip paths.
    fileprivate func decodePersistedFiles(from data: Data?) -> [PersistedFile] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([PersistedFile].self, from: data)) ?? []
    }
}
