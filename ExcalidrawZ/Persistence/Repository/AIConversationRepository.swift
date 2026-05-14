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

struct AIConversationFileScope: Hashable, Sendable {
    enum Kind: String, Sendable {
        case libraryFile
        case localFile
        case temporaryFile
        case collaborationFile
    }

    var kind: Kind
    var id: String
}

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
    var fileScopeKind: String?
    var fileScopeID: String?
    var toolsData: Data?
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
    /// Compact-out marker: this row was rolled into a later
    /// `isCompactSummary` and is no longer sent to the LLM. The UI
    /// still renders it (dimmed) so the user can scroll back through
    /// pre-compaction history.
    var isCompactedOut: Bool
    /// "Earlier conversation summary" marker. UI renders these as a
    /// distinct summary card rather than a normal user bubble.
    var isCompactSummary: Bool
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
                            filesData: msg.filesData,
                            isCompactedOut: msg.isCompactedOut,
                            isCompactSummary: msg.isCompactSummary
                        )
                    }
                return AIConversationSnapshot(
                    conversationID: row.conversationID,
                    type: row.type,
                    title: row.title,
                    createdAt: row.createdAt,
                    lastChatAt: row.lastChatAt,
                    fileScopeKind: row.fileScopeKind,
                    fileScopeID: row.fileScopeID,
                    toolsData: row.toolsData,
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

    /// Fetch snapshots of every conversation associated with the given
    /// active-file scope. The scope is intentionally independent of
    /// Core Data relationships so library files, local URLs,
    /// temporary URLs, and collaboration files all use the same lookup
    /// path.
    ///
    func fetchConversationSnapshots(
        forFileScope scope: AIConversationFileScope
    ) async throws -> [AIConversationSnapshot] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = Self.fileScopePredicate(scope)
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "lastChatAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            fetchRequest.relationshipKeyPathsForPrefetching = ["messages"]

            let rows = try context.fetch(fetchRequest)
            print("[AIChatDiag] repo.fetchConversationSnapshots(scope=\(scope.kind.rawValue):\(scope.id)) -> \(rows.count) Core Data rows")
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
                            filesData: msg.filesData,
                            isCompactedOut: msg.isCompactedOut,
                            isCompactSummary: msg.isCompactSummary
                        )
                    }
                return AIConversationSnapshot(
                    conversationID: row.conversationID,
                    type: row.type,
                    title: row.title,
                    createdAt: row.createdAt,
                    lastChatAt: row.lastChatAt,
                    fileScopeKind: row.fileScopeKind,
                    fileScopeID: row.fileScopeID,
                    toolsData: row.toolsData,
                    messages: messageSnapshots
                )
            }
        }
    }

    /// Bind an existing conversation to an active-file scope. Used as a
    /// post-create step after `LLMKit.createConversation(...)` returns
    /// — LLMKit's API doesn't carry our app's file scope, so we
    /// stamp it on out-of-band. Idempotent: re-binding to the same
    /// scope is a no-op; binding to a different file replaces the
    /// previous link.
    func bindConversationToFileScope(
        conversationID: String,
        scope: AIConversationFileScope
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)
            fetchRequest.fetchLimit = 1

            guard let conversation = try context.fetch(fetchRequest).first else {
                print("[AIChatDiag] repo.bindConversationToFileScope: conversation \(conversationID) NOT FOUND in Core Data")
                throw AppError.fileError(.notFound)
            }
            conversation.fileScopeKind = scope.kind.rawValue
            conversation.fileScopeID = scope.id
            try context.save()
            print("[AIChatDiag] repo.bindConversationToFileScope: bound \(conversationID) -> \(scope.kind.rawValue):\(scope.id)")
        }
    }

    /// Move existing conversations from one file scope to another.
    /// Used when URL-backed files are renamed or moved, and when a
    /// temporary file is saved into a durable local file.
    func rebindConversations(
        from oldScope: AIConversationFileScope,
        to newScope: AIConversationFileScope
    ) async throws {
        guard oldScope != newScope else { return }

        let context = PersistenceController.shared.newTaskContext()
        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = Self.fileScopePredicate(oldScope)

            let conversations = try context.fetch(fetchRequest)
            for conversation in conversations {
                conversation.fileScopeKind = newScope.kind.rawValue
                conversation.fileScopeID = newScope.id
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - Create Operations

    /// Create a new conversation. File scope is stamped separately by
    /// app-level send wiring because LLMKit conversations don't carry
    /// ExcalidrawZ file ownership.
    /// - Returns: The objectID of the created conversation
    func createConversation(
        conversationID: String,
        title: String,
        type: String,
        toolsData: Data? = nil
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let conversation = AIConversation(context: context)
            conversation.conversationID = conversationID
            conversation.title = title
            conversation.type = type
            conversation.toolsData = toolsData
            conversation.createdAt = Date()
            conversation.lastChatAt = Date()

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
        isCompactedOut: Bool = false,
        isCompactSummary: Bool = false,
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
            message.isCompactedOut = isCompactedOut
            message.isCompactSummary = isCompactSummary
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

    /// Persist the conversation-level tool roster used to rebuild
    /// `Conversation.agentConfig.tools` on restore.
    func updateTools(
        conversationID: String,
        toolsData: Data?
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = NSPredicate(format: "conversationID == %@", conversationID)
            fetchRequest.fetchLimit = 1

            guard let conversation = try context.fetch(fetchRequest).first else {
                throw AppError.fileError(.notFound)
            }

            conversation.toolsData = toolsData
            try context.save()
        }
    }

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
        clearFiles: Bool = false,
        // Compact-state flags. Both default to nil so omitting them
        // leaves the persisted value alone — the only callers that pass
        // an explicit value are LLMKit-driven `compactConversation`
        // updates that set `isCompactedOut = true` and the summary
        // insertion (which goes through `createMessage` instead).
        isCompactedOut: Bool? = nil,
        isCompactSummary: Bool? = nil
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

            if let isCompactedOut {
                message.isCompactedOut = isCompactedOut
            }

            if let isCompactSummary {
                message.isCompactSummary = isCompactSummary
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
        let blobs = try await deleteConversationRows {
            NSPredicate(format: "conversationID == %@", conversationID)
        }
        await deleteAttachments(from: blobs)
    }

    /// Delete every conversation tied to a file scope. This is the
    /// replacement for the old Core Data relationship cleanup path:
    /// once the file's backing record or URL is gone, its scoped
    /// conversations should not remain resumable.
    func deleteConversations(forFileScope scope: AIConversationFileScope) async throws {
        let blobs = try await deleteConversationRows {
            Self.fileScopePredicate(scope)
        }
        await deleteAttachments(from: blobs)
    }

    private func deleteConversationRows(
        matching makePredicate: @escaping @Sendable () -> NSPredicate
    ) async throws -> [Data] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.predicate = makePredicate()
            fetchRequest.relationshipKeyPathsForPrefetching = ["messages"]

            let conversations = try context.fetch(fetchRequest)
            guard !conversations.isEmpty else {
                return []
            }

            var blobs: [Data] = []
            for conversation in conversations {
                let messages = conversation.messages as? Set<AIConversationMessage> ?? []
                blobs.append(contentsOf: messages.compactMap(\.filesData))
                for message in messages {
                    context.delete(message)
                }
                context.delete(conversation)
            }

            if context.hasChanges {
                try context.save()
            }
            return blobs
        }
    }

    private func deleteAttachments(from blobs: [Data]) async {
        let referenced = blobs.flatMap(Self.decodePersistedFiles(from:))
        await PersistenceController.shared.aiChatAttachmentRepository.deleteAll(referencedFiles: referenced)
    }

    private static func fileScopePredicate(_ scope: AIConversationFileScope) -> NSPredicate {
        NSPredicate(
            format: "fileScopeKind == %@ AND fileScopeID == %@",
            scope.kind.rawValue,
            scope.id
        )
    }

    private static func decodePersistedFiles(from data: Data?) -> [PersistedFile] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([PersistedFile].self, from: data)) ?? []
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
