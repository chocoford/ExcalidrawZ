//
//  WebFetchTool.swift
//  AIppo
//
//  Created by Chocoford on 11/18/25.
//

import Foundation
import LLMCore

struct WebFetchTool: Tool {
    var name: String { "web_fetch" }

    var description: String {
        "Fetch and retrieve content from a specific URL. Use this when you have an exact URL to access."
    }

    var parameters: ToolParameters {
        ToolParameters(
            properties: [
                "url": ParameterProperty(
                    type: "string",
                    description: "The exact URL to fetch content from"
                )
            ],
            required: ["url"]
        )
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> String {
        guard let inputData = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
              let urlString = json["url"] as? String,
              let url = URL(string: urlString) else {
            throw ToolError.invalidInput("Invalid URL parameter")
        }

        // Create URLRequest with proper headers
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0

        do {
            // Fetch content using URLSession
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ToolError.executionFailed("Failed to fetch URL: Invalid response")
            }

            guard let content = String(data: responseData, encoding: .utf8) else {
                throw ToolError.executionFailed("Failed to decode URL content")
            }

            // Strip HTML tags for better readability
            let stripped = content
                .replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
                .replacingOccurrences(of: "\\s+", with: " ", options: [.regularExpression])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Limit content length
            let maxLength = 2000
            if stripped.count > maxLength {
                return String(stripped.prefix(maxLength)) + "..."
            }

            return stripped
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed("Failed to fetch URL: \(error.localizedDescription)")
        }
    }
}
