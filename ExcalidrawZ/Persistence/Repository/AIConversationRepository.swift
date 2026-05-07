//
//  AIConversationRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/11.
//

import Foundation
import CoreData
import Logging

// MARK: - Snapshots

/// Value-type snapshot of an `AIConversation` row + its messages.
/// Crossing the Core Data context boundary requires either staying on
/// the context's queue or extracting plain values inside it — managed
/// objects accessed off-queue return undefined data, with relationship
/// faults in particular collapsing to empty sets. The repo populates
/// these snapshots inside `context.perform` so callers can do async
/// follow-up work (e.g. attachment file resolution) without touching
/// `NSManagedObject` from the wrong queue.
struct AIConversationSnapshot: Sendable {
    var conversationID: String?
    var type: String?
    var title: String?
    var createdAt: Date?
    var lastChatAt: Date?
    var messages: [AIConversationMessageSnapshot]
}

struct AIConversationMessageSnapshot: Sendable {
    var messageID: String?
    var messageType: String?
    var content: String?
    var role: String?
    var timeStamp: Date?
    var usageConsumed: Double
    var usageRemains: Double
    var toolCallsData: Data?
    var toolCallId: String?
    var filesData: Data?
}

/// Actor responsible for AIConversation and AIConversationMessage entity operations
actor AIConversationRepository {
    private let logger = Logger(label: "AIConversationRepository")

    // MARK: - Read Operations

    /// Fetch all conversations + their messages as Sendable snapshots,
    /// fully extracted from Core Data inside one `context.perform`
    /// block. Callers (most notably `LLMPersistenceProvider`) do
    /// async follow-up — e.g. JSON-decoding `filesData`, resolving
    /// attachment URLs — entirely on the snapshot, never on the
    /// underlying managed objects. This is the only safe pattern for
    /// crossing the Core Data context queue with relationship data.
    ///
    /// Pre-fetches the `messages` relationship via
    /// `relationshipKeyPathsForPrefetching` so the inner property
    /// reads don't trigger an N+1 chain of fault fires.
    func fetchAllConversationSnapshots() async throws -> [AIConversationSnapshot] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "lastChatAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            fetchRequest.relationshipKeyPathsForPrefetching = ["messages"]

            let rows = try context.fetch(fetchRequest)
            return rows.map { row in
                let messageSet = row.messages as? Set<AIConversationMessage> ?? []
                let messageSnapshots = messageSet
                    .sorted { ($0.timeStamp ?? Date()) < ($1.timeStamp ?? Date()) }
                    .map { msg in
                        AIConversationMessageSnapshot(
                            messageID: msg.messageID,
                            messageType: msg.messageType,
                            content: msg.content,
                            role: msg.role,
                            timeStamp: msg.timeStamp,
                            usageConsumed: msg.usageConsumed,
                            usageRemains: msg.usageRemains,
                            toolCallsData: msg.toolCallsData,
                            toolCallId: msg.toolCallId,
                            filesData: msg.filesData
                        )
                    }
                return AIConversationSnapshot(
                    conversationID: row.conversationID,
                    type: row.type,
                    title: row.title,
                    createdAt: row.createdAt,
                    lastChatAt: row.lastChatAt,
                    messages: messageSnapshots
                )
            }
        }
    }

    /// Fetch a specific conversation by conversationID
    /// - Parameter conversationID: The conversation identifier
    /// - Returns: The AIConversation entity or nil if not found
    func fetchConversation(conversationID: String) async throws -> AIConversation? {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)
            fetchRequest.fetchLimit = 1

            return try context.fetch(fetchRequest).first
        }
    }

    /// Fetch the snapshots of every conversation associated with the
    /// given `File` (matched by File.id UUID). Same snapshot pattern as
    /// `fetchAllConversationSnapshots` — all NSManagedObject reads
    /// happen inside `context.perform`, output is plain Sendable
    /// values safe to pass across actor / queue boundaries.
    ///
    /// - Parameter fileID: The `File.id` UUID. Pass `nil` to query
    ///   "conversations with no file association" (e.g. legacy rows
    ///   from before file-binding was wired in, or sessions started
    ///   on local/temporary files where binding doesn't apply).
    /// - Returns: Snapshots for matching conversations, ordered by
    ///   `lastChatAt` descending then `createdAt` descending. Empty
    ///   array if no matches.
    func fetchConversationSnapshots(forFileID fileID: UUID?) async throws -> [AIConversationSnapshot] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            if let fileID {
                fetchRequest.predicate = NSPredicate(format: "file.id == %@", fileID as CVarArg)
            } else {
                // `file == nil` syntax in NSPredicate uses the explicit
                // `== NULL` form to match unbound rows.
                fetchRequest.predicate = NSPredicate(format: "file == NULL")
            }
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "lastChatAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            fetchRequest.relationshipKeyPathsForPrefetching = ["messages"]

            let rows = try context.fetch(fetchRequest)
            print("[AIChatDiag] repo.fetchConversationSnapshots(forFileID=\(fileID?.uuidString ?? "nil")) -> \(rows.count) Core Data rows")
            return rows.map { row in
                let messageSet = row.messages as? Set<AIConversationMessage> ?? []
                let messageSnapshots = messageSet
                    .sorted { ($0.timeStamp ?? Date()) < ($1.timeStamp ?? Date()) }
                    .map { msg in
                        AIConversationMessageSnapshot(
                            messageID: msg.messageID,
                            messageType: msg.messageType,
                            content: msg.content,
                            role: msg.role,
                            timeStamp: msg.timeStamp,
                            usageConsumed: msg.usageConsumed,
                            usageRemains: msg.usageRemains,
                            toolCallsData: msg.toolCallsData,
                            toolCallId: msg.toolCallId,
                            filesData: msg.filesData
                        )
                    }
                return AIConversationSnapshot(
                    conversationID: row.conversationID,
                    type: row.type,
                    title: row.title,
                    createdAt: row.createdAt,
                    lastChatAt: row.lastChatAt,
                    messages: messageSnapshots
                )
            }
        }
    }

    /// Bind an existing conversation to a `File`. Used as a
    /// post-create step after `LLMKit.createConversation(...)` returns
    /// — LLMKit's API doesn't carry our app's file association, so we
    /// stamp it on out-of-band. Idempotent: re-binding to the same
    /// file is a no-op; binding to a different file replaces the
    /// previous link.
    ///
    /// - Parameters:
    ///   - conversationID: Conversation identifier (string id used in
    ///     LLMKit), not the NSManagedObjectID.
    ///   - fileObjectID: The File entity's permanent objectID. Caller
    ///     must have already saved the File row.
    func bindConversationToFile(
        conversationID: String,
        fileObjectID: NSManagedObjectID
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)
            fetchRequest.fetchLimit = 1

            guard let conversation = try context.fetch(fetchRequest).first else {
                print("[AIChatDiag] repo.bindConversationToFile: conversation \(conversationID) NOT FOUND in Core Data")
                throw AppError.fileError(.notFound)
            }
            guard let file = context.object(with: fileObjectID) as? File else {
                print("[AIChatDiag] repo.bindConversationToFile: File at objectID \(fileObjectID) cast failed")
                throw AppError.fileError(.notFound)
            }
            conversation.file = file
            try context.save()
            print("[AIChatDiag] repo.bindConversationToFile: bound \(conversationID) -> File(name=\(file.name ?? "?") id=\(file.id?.uuidString ?? "nil"))")
        }
    }

    // MARK: - Create Operations

    /// Create a new conversation
    /// - Parameters:
    ///   - conversationID: Unique conversation identifier
    ///   - title: Conversation title
    ///   - type: Conversation type (e.g., "Chat")
    ///   - fileObjectID: Optional associated file objectID
    /// - Returns: The objectID of the created conversation
    func createConversation(
        conversationID: String,
        title: String,
        type: String,
        fileObjectID: NSManagedObjectID? = nil
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let conversation = AIConversation(context: context)
            conversation.conversationID = conversationID
            conversation.title = title
            conversation.type = type
            conversation.createdAt = Date()
            conversation.lastChatAt = Date()

            if let fileObjectID = fileObjectID {
                if let file = context.object(with: fileObjectID) as? File {
                    conversation.file = file
                }
            }

            context.insert(conversation)
            try context.save()

            return conversation.objectID
        }
    }

    /// Create a new message in a conversation
    /// - Parameters:
    ///   - messageID: Unique message identifier
    ///   - messageType: Message type ("content", "agentStep", "error")
    ///   - content: Message content
    ///   - role: Message role ("user", "assistant", "system", "tool", "developer")
    ///   - toolCallsData: JSON-encoded `[ToolCall]` carried by an assistant
    ///     message. Required for native tool-use roundtrip — without it,
    ///     a restored conversation can't reconstruct the model's pending
    ///     tool calls and the next provider request will be malformed.
    ///   - toolCallId: For `role == .tool` messages, the id of the matching
    ///     assistant `toolCall`. Required by OpenAI/Anthropic to associate
    ///     tool results with the call that produced them.
    ///   - filesData: JSON-encoded `[PersistedFile]` — references to
    ///     attachments (images, etc.) carried by this message. Bytes
    ///     live in `AIChatAttachments/` under managed file storage,
    ///     synced via iCloud Drive; this column only stores the index.
    ///   - conversationObjectID: Parent conversation objectID
    /// - Returns: The objectID of the created message
    func createMessage(
        messageID: String,
        messageType: String,
        content: String,
        role: String,
        toolCallsData: Data? = nil,
        toolCallId: String? = nil,
        filesData: Data? = nil,
        conversationObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            guard let conversation = context.object(with: conversationObjectID) as? AIConversation else {
                throw AppError.fileError(.notFound)
            }

            let message = AIConversationMessage(context: context)
            message.messageID = messageID
            message.messageType = messageType
            message.content = content
            message.role = role
            message.toolCallsData = toolCallsData
            message.toolCallId = toolCallId
            message.filesData = filesData
            message.timeStamp = Date()
            message.conversation = conversation

            context.insert(message)

            // Update conversation's lastChatAt
            conversation.lastChatAt = Date()

            try context.save()

            return message.objectID
        }
    }

    // MARK: - Update Operations

    /// Update conversation title
    /// - Parameters:
    ///   - conversationObjectID: The conversation objectID
    ///   - title: New title
    func updateTitle(
        conversationObjectID: NSManagedObjectID,
        title: String
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            guard let conversation = context.object(with: conversationObjectID) as? AIConversation else {
                throw AppError.fileError(.notFound)
            }

            conversation.title = title
            try context.save()
        }
    }

    /// Update message content and usage. Each parameter follows
    /// "skip if nil; write if `.some`" semantics so callers can patch a
    /// subset without clobbering unrelated fields. The exception is
    /// `clearToolCalls` / `clearToolCallId`, which let a caller actively
    /// erase a previously-set value (an assistant message can drop its
    /// pending tool calls if the model retracts them).
    /// - Parameters:
    ///   - messageObjectID: The message objectID
    ///   - content: New content (optional — pass `nil` to leave unchanged)
    ///   - usageConsumed: Token usage consumed (optional)
    ///   - usageRemains: Token usage remains (optional)
    ///   - toolCallsData: JSON-encoded `[ToolCall]` (optional — leaves
    ///     unchanged if `nil`; pass `clearToolCalls: true` to wipe)
    ///   - clearToolCalls: If true, sets `toolCallsData` to nil regardless
    ///     of `toolCallsData` parameter.
    ///   - toolCallId: New tool-call id (optional)
    ///   - clearToolCallId: If true, sets `toolCallId` to nil.
    func updateMessage(
        messageObjectID: NSManagedObjectID,
        content: String? = nil,
        usageConsumed: Double? = nil,
        usageRemains: Double? = nil,
        toolCallsData: Data? = nil,
        clearToolCalls: Bool = false,
        toolCallId: String? = nil,
        clearToolCallId: Bool = false,
        filesData: Data? = nil,
        clearFiles: Bool = false
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            guard let message = context.object(with: messageObjectID) as? AIConversationMessage else {
                throw AppError.fileError(.notFound)
            }

            if let content = content {
                message.content = content
            }

            if let consumed = usageConsumed {
                message.usageConsumed = consumed
            }

            if let remains = usageRemains {
                message.usageRemains = remains
            }

            if clearToolCalls {
                message.toolCallsData = nil
            } else if let toolCallsData = toolCallsData {
                message.toolCallsData = toolCallsData
            }

            if clearToolCallId {
                message.toolCallId = nil
            } else if let toolCallId = toolCallId {
                message.toolCallId = toolCallId
            }

            if clearFiles {
                message.filesData = nil
            } else if let filesData = filesData {
                message.filesData = filesData
            }

            message.timeStamp = Date()

            // Update conversation's lastChatAt
            if let conversation = message.conversation {
                conversation.lastChatAt = Date()
            }

            try context.save()
        }
    }

    /// Update agent step message
    /// - Parameters:
    ///   - messageObjectID: The message objectID
    ///   - stepNumber: Agent step number
    ///   - stepType: Step type ("thought", "action", "observation", etc.)
    ///   - content: Step content
    func updateAgentStepMessage(
        messageObjectID: NSManagedObjectID,
        stepNumber: Int,
        stepType: String,
        content: String
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            guard let message = context.object(with: messageObjectID) as? AIConversationMessage else {
                throw AppError.fileError(.notFound)
            }

            message.stepNumber = Int64(stepNumber)
            message.stepType = stepType
            message.content = content
            message.timeStamp = Date()

            // Update conversation's lastChatAt
            if let conversation = message.conversation {
                conversation.lastChatAt = Date()
            }

            try context.save()
        }
    }

    // MARK: - Delete Operations

    /// Delete messages by messageIDs
    /// - Parameter messageIDs: Array of message identifiers to delete
    func deleteMessages(messageIDs: [String]) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversationMessage>(entityName: "AIConversationMessage")
            fetchRequest.predicate = NSPredicate(format: "messageID IN %@", messageIDs)

            let messages = try context.fetch(fetchRequest)

            for message in messages {
                context.delete(message)
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    /// Delete entire conversation and all its messages
    /// - Parameter conversationID: The conversation identifier
    func deleteConversation(conversationID: String) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)

            guard let conversation = try context.fetch(fetchRequest).first else {
                return // Already deleted
            }

            // Core Data will handle cascading delete of messages based on deletion rule
            context.delete(conversation)
            try context.save()
        }
    }

    // MARK: - Helper Methods

    /// Find message by messageID
    /// - Parameter messageID: The message identifier
    /// - Returns: The NSManagedObjectID of the message or nil if not found
    func findMessageObjectID(messageID: String) async throws -> NSManagedObjectID? {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversationMessage>(entityName: "AIConversationMessage")
            fetchRequest.predicate = NSPredicate(format: "messageID == %@", messageID)
            fetchRequest.fetchLimit = 1

            return try context.fetch(fetchRequest).first?.objectID
        }
    }

    /// Find conversation objectID by conversationID
    /// - Parameter conversationID: The conversation identifier
    /// - Returns: The NSManagedObjectID of the conversation or nil if not found
    func findConversationObjectID(conversationID: String) async throws -> NSManagedObjectID? {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)
            fetchRequest.fetchLimit = 1

            return try context.fetch(fetchRequest).first?.objectID
        }
    }

    // MARK: - Files Data Queries

    /// Collect every `filesData` blob that belongs to messages of the
    /// given conversation. Used by `LLMPersistenceProvider` immediately
    /// before deleting a conversation: cascade delete in Core Data
    /// will drop the message rows, but the on-disk attachment files
    /// would be orphaned without an explicit pre-delete sweep.
    /// - Parameter conversationID: The conversation identifier
    /// - Returns: One `Data` per message that has a non-nil `filesData`.
    func fetchFilesDataBlobs(forConversationID conversationID: String) async throws -> [Data] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversationMessage>(entityName: "AIConversationMessage")
            fetchRequest.predicate = NSPredicate(
                format: "conversation.conversationID == %@ AND filesData != nil",
                conversationID
            )
            fetchRequest.propertiesToFetch = ["filesData"]

            let messages = try context.fetch(fetchRequest)
            return messages.compactMap { $0.filesData }
        }
    }

    /// Collect every `filesData` blob across the whole store. Used by
    /// the AI chat attachment GC sweep on app launch — caller decodes
    /// each blob into `[PersistedFile]`, unions the local fileIDs, and
    /// passes the result to the attachment repo so it can delete any
    /// on-disk file not in that set.
    /// - Returns: One `Data` per message that has a non-nil `filesData`.
    func fetchAllFilesDataBlobs() async throws -> [Data] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversationMessage>(entityName: "AIConversationMessage")
            fetchRequest.predicate = NSPredicate(format: "filesData != nil")
            fetchRequest.propertiesToFetch = ["filesData"]

            let messages = try context.fetch(fetchRequest)
            return messages.compactMap { $0.filesData }
        }
    }
}
