//
//  FinalAnswerTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore

/// Tool to output the final response to the user.
struct FinalAnswerTool: Tool {
    var name: String { "final_answer" }

    var displayName: String { String(localizable: .aiChatToolFinalAnswerName) }

    var description: String {
        "Return the final response to the user."
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "answer": ParameterProperty(
                    type: "string",
                    description: "The final response text to display to the user."
                )
            ],
            required: ["answer"]
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Invalid input format. Expected: {\"answer\": \"...\"}")
        }

        let answer = (json["answer"] ?? json["content"] ?? json["text"]) as? String
        guard let answer, !answer.isEmpty else {
            throw ToolError.invalidInput("Missing answer text")
        }

        return .text(answer)
    }
}
