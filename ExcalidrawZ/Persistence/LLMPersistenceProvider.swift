//
//  LLMPersistenceProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 2026/01/11.
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
    
    // MARK: - Restore Conversations
    
    func restoreConversations() async throws -> [LLMKit.Conversation] {
        let conversations = try await repository.fetchAllConversations()
        
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
        
        print("Restored \(llmConversations.count) conversations from Core Data.")
        return llmConversations
    }
    
    // MARK: - Update Conversation
    
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
    
    // MARK: - Private Helpers
    
    /// Convert Core Data AIConversation to LLMKit Conversation
    private func convertToLLMKitConversation(_ coreDataConversation: AIConversation) async -> LLMKit.Conversation? {
        // Get messages from relationship
        let messageSet = coreDataConversation.messages as? Set<AIConversationMessage> ?? []
        let sortedMessages = messageSet.sorted { ($0.timeStamp ?? Date()) < ($1.timeStamp ?? Date()) }
        
        // Convert messages
        let chatMessages = sortedMessages.compactMap { convertToLLMKitMessage($0) }
        
        // Determine conversation type
        let conversationType: LLMKit.Conversation.ConversationTpye
        let type = coreDataConversation.type ?? "Chat"
        switch type {
            case "Chat":
                conversationType = .custom("Chat")
            default:
                conversationType = .custom(type)
        }
        
        // Create LLMKit Conversation
        return LLMKit.Conversation(
            id: coreDataConversation.conversationID ?? UUID().uuidString,
            type: conversationType,
            agentConfig: .chat, // Default to chat, agentConfig not persisted in Core Data yet
            title: coreDataConversation.title ?? "Untitled",
            messages: chatMessages,
            createdAt: coreDataConversation.createdAt ?? Date(),
            lastChatAt: coreDataConversation.lastChatAt ?? Date()
        )
    }
    
    /// Convert Core Data AIConversationMessage to ChatMessage
    private func convertToLLMKitMessage(_ coreDataMessage: AIConversationMessage) -> ChatMessage? {
        let messageType = coreDataMessage.messageType ?? "content"
        
        switch messageType {
            case "content":
                let role: ChatMessageContent.Role = (coreDataMessage.role == "user") ? .user : .assistant
                
                // Convert usage from separate fields to CreditsResult
                let usage: CreditsResult?
                let consumed = coreDataMessage.usageConsumed
                let remains = coreDataMessage.usageRemains
                usage = CreditsResult(consumed: consumed, remains: remains)
                
                let content = ChatMessageContent(
                    id: coreDataMessage.messageID ?? UUID().uuidString,
                    role: role,
                    content: coreDataMessage.content ?? "",
                    files: [], // Files not implemented yet
                    usage: usage
                )
                return .content(content)
                
            case "agentStep":
                let stepType = AgentStep.StepType(rawValue: coreDataMessage.stepType ?? "thought") ?? .thought
                let step = AgentStep(
                    id: UUID(uuidString: coreDataMessage.messageID ?? "") ?? UUID(),
                    stepNumber: Int(coreDataMessage.stepNumber),
                    type: stepType,
                    content: coreDataMessage.content ?? "",
                    timestamp: coreDataMessage.timeStamp ?? Date()
                )
                return .agentStep(step)
                
            case "error":
                return .error(
                    UUID(uuidString: coreDataMessage.messageID ?? "") ?? UUID(),
                    coreDataMessage.content ?? "Unknown error"
                )
                
            default:
                return nil
        }
    }
    
    /// Insert a new conversation
    private func insertConversation(_ conversation: LLMKit.Conversation) async throws {
        let conversationType = conversation.type.rawValue
        
        // Create conversation in Core Data
        let conversationObjectID = try await repository.createConversation(
            conversationID: conversation.id,
            title: conversation.title,
            type: conversationType,
            fileObjectID: nil // File association not implemented yet
        )
        
        // Create all messages
        for message in conversation.messages {
            try await createMessageFromChatMessage(
                message,
                conversationObjectID: conversationObjectID
            )
        }
    }
    
    /// Update conversation with specific action
    private func updateConversationAction(conversationID: String, action: ChatMessageUpdateAction) async throws {
        // Find conversation objectID
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
    
    /// Create a message from ChatMessage
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
                    conversationObjectID: conversationObjectID
                )
                
                // Update usage if available
                if let usage = message.usage {
                    try await repository.updateMessage(
                        messageObjectID: messageObjectID,
                        usageConsumed: usage.consumed,
                        usageRemains: usage.remains
                    )
                }
                
            case .agentStep(let step):
                let messageObjectID = try await repository.createMessage(
                    messageID: step.id.uuidString,
                    messageType: "agentStep",
                    content: step.content,
                    role: "assistant",
                    conversationObjectID: conversationObjectID
                )
                
                // Update agent step details
                try await repository.updateAgentStepMessage(
                    messageObjectID: messageObjectID,
                    stepNumber: step.stepNumber,
                    stepType: step.type.rawValue,
                    content: step.content
                )
                
            case .error(let id, let errorMessage):
                _ = try await repository.createMessage(
                    messageID: id.uuidString,
                    messageType: "error",
                    content: errorMessage,
                    role: "system",
                    conversationObjectID: conversationObjectID
                )
                
            case .loading:
                // Don't persist loading messages
                break
        }
    }
    
    /// Update an existing message from ChatMessage
    private func updateMessageFromChatMessage(_ chatMessage: ChatMessage) async throws {
        switch chatMessage {
            case .content(let content):
                // Find message objectID
                guard let messageObjectID = try await repository.findMessageObjectID(messageID: content.id) else {
                    return // Message doesn't exist, skip
                }
                
                // Update message with usage if available
                try await repository.updateMessage(
                    messageObjectID: messageObjectID,
                    content: content.content,
                    usageConsumed: content.usage?.consumed,
                    usageRemains: content.usage?.remains
                )
                
            case .agentStep(let step):
                // Find message objectID
                guard let messageObjectID = try await repository.findMessageObjectID(messageID: step.id.uuidString) else {
                    return
                }
                
                // Update agent step
                try await repository.updateAgentStepMessage(
                    messageObjectID: messageObjectID,
                    stepNumber: step.stepNumber,
                    stepType: step.type.rawValue,
                    content: step.content
                )
                
            case .error(let id, let errorMessage):
                // Find message objectID
                guard let messageObjectID = try await repository.findMessageObjectID(messageID: id.uuidString) else {
                    return
                }
                
                // Update error message
                try await repository.updateMessage(
                    messageObjectID: messageObjectID,
                    content: errorMessage
                )
                
            case .loading:
                // Don't update loading messages
                break
        }
    }
}
