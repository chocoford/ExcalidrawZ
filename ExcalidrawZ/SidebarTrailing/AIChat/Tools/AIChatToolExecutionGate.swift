//
//  AIChatToolExecutionGate.swift
//  ExcalidrawZ
//

import LLMCore

enum AIChatToolExecutionGate {
    static func ensureAIEnabled() throws {
        guard AIChatAvailability.canUseAI else {
            throw ToolError.executionFailed("AI features are disabled.")
        }
    }
}
