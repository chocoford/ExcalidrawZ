//
//  DateTimeTool.swift
//  AIppo
//
//  Created by Claude Code
//

import Foundation
import LLMCore

/// Tool to get current date and time information
struct DateTimeTool: Tool {
    var name: String { "datetime" }

    var displayName: String { String(localizable: .aiChatToolDateTimeName) }

    var description: String {
        "Get current date and time information in various formats. Can also calculate time differences and convert timezones."
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "action": ParameterProperty(
                    type: "string",
                    description: "The action to perform",
                    enum: ["current", "timezone", "format"]
                ),
                "timezone": ParameterProperty(
                    type: "string",
                    description: "Optional timezone identifier (e.g., 'America/New_York', 'Asia/Tokyo'). Only used for 'timezone' action."
                ),
                "format": ParameterProperty(
                    type: "string",
                    description: "Optional date format (e.g., 'yyyy-MM-dd HH:mm:ss'). Only used for 'format' action."
                )
            ],
            required: ["action"]
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        // Parse input JSON
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            throw ToolError.invalidInput("Invalid input format. Expected: {\"action\": \"current\"}")
        }

        let now = Date()

        switch action {
        case "current":
            return .text(formatCurrentDateTime(now))

        case "timezone":
            guard let timezoneId = json["timezone"] as? String,
                  let timezone = TimeZone(identifier: timezoneId) else {
                throw ToolError.invalidInput("Invalid or missing timezone identifier")
            }
            return .text(formatDateTimeInTimezone(now, timezone: timezone))

        case "format":
            guard let formatString = json["format"] as? String else {
                throw ToolError.invalidInput("Missing format string")
            }
            return .text(formatDateTime(now, format: formatString))

        default:
            throw ToolError.invalidInput("Invalid action. Use 'current', 'timezone', or 'format'")
        }
    }

    private func formatCurrentDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full

        let dateString = formatter.string(from: date)
        let calendar = Calendar.current
        // let weekday = calendar.component(.weekday, from: date)
        let weekNumber = calendar.component(.weekOfYear, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0

        return """
        Current Date and Time:
        \(dateString)
        Week: \(weekNumber)
        Day of year: \(dayOfYear)
        Unix timestamp: \(Int(date.timeIntervalSince1970))
        """
    }

    private func formatDateTimeInTimezone(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        formatter.timeZone = timezone

        return """
        Date and Time in \(timezone.identifier):
        \(formatter.string(from: date))
        """
    }

    private func formatDateTime(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format

        return formatter.string(from: date)
    }
}
