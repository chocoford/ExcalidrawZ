//
//  CalculatorTool.swift
//  AIppo
//
//  Created by Claude Code
//

import Foundation
import LLMCore

/// Simple calculator tool for basic math operations
struct CalculatorTool: Tool {
    var name: String { "calculator" }

    var description: String {
        "Perform basic mathematical calculations. Supports +, -, *, /, ^, sqrt, sin, cos, tan, log, ln, and parentheses."
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "expression": ParameterProperty(
                    type: "string",
                    description: "The mathematical expression to evaluate (e.g., '2 + 2', 'sqrt(16)', 'sin(3.14159/2)')"
                )
            ],
            required: ["expression"]
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        // Parse input JSON
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expression = json["expression"] as? String else {
            throw ToolError.invalidInput("Invalid input format. Expected: {\"expression\": \"2 + 2\"}")
        }

        do {
            let result = try evaluate(expression)
            return .text("Result: \(result)")
        } catch {
            throw ToolError.executionFailed("Failed to evaluate expression: \(error.localizedDescription)")
        }
    }

    private func evaluate(_ expression: String) throws -> Double {
        // Use NSExpression for safe evaluation
        let cleanExpression = expression
            .replacingOccurrences(of: "^", with: "**")  // Power operator
            .replacingOccurrences(of: "sqrt", with: "sqrt")

        // For simple expressions, use NSExpression
        let exp = NSExpression(format: cleanExpression)

        guard let result = exp.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw ToolError.executionFailed("Could not evaluate expression")
        }

        return result.doubleValue
    }
}
