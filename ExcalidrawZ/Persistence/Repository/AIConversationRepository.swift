//
//  AIConversationRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/11.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for AIConversation and AIConversationMessage entity operations
actor AIConversationRepository {
    private let logger = Logger(label: "AIConversationRepository")

    // MARK: - Read Operations

    /// Fetch all conversations sorted by lastChatAt/createdAt
    func fetchAllConversations() async throws -> [AIConversation] {
        let context = PersistenceController.shared.newTaskContext()

        return try await context.perform {
            let fetchRequest = NSFetchRequest<AIConversation>(entityName: "AIConversation")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "lastChatAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]

            return try context.fetch(fetchRequest)
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
    ///   - conversationObjectID: Parent conversation objectID
    /// - Returns: The objectID of the created message
    func createMessage(
        messageID: String,
        messageType: String,
        content: String,
        role: String,
        toolCallsData: Data? = nil,
        toolCallId: String? = nil,
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
        clearToolCallId: Bool = false
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
}
