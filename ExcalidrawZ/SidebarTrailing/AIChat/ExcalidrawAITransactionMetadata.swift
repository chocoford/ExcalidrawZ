//
//  ExcalidrawAITransactionMetadata.swift
//  ExcalidrawZ
//
//  Business metadata attached to AI chat requests for server-side
//  attribution and client-side usage presentation.
//

import Foundation

enum ExcalidrawAITransactionSource: String, Codable, Equatable, Sendable {
    case aiChatSidebar = "ai-chat-sidebar"
}

enum ExcalidrawAITransactionRequestKind: String, Codable, Equatable, Sendable {
    case createConversation
    case sendMessage
}

struct ExcalidrawAITransactionMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let source: ExcalidrawAITransactionSource
    let conversationID: String
    let userMessageID: String
    let requestKind: ExcalidrawAITransactionRequestKind
    let agentID: String
    let model: String
    let canvasTarget: String
    let fileID: String?
    let fileName: String?
    let fileKind: String?
    let selectedElementCount: Int
    let attachmentCount: Int
    let hasCurrentFileData: Bool
    let isNewConversation: Bool
}
