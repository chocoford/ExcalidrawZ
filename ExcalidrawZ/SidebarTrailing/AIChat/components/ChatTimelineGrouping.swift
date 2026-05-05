//
//  ChatTimelineGrouping.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  Pure data transforms over a `[ChatMessage]` timeline. `groupMessages`
//  flattens the raw timeline into renderable rows (`MessageGroup`):
//  consecutive assistant + tool messages from one agent turn collapse into a
//  single `assistantRound`, system/developer scaffolding is dropped.
//
//  `parseFinalAnswerArgs` extracts the user-facing text from a `final_answer`
//  tool-call's JSON arguments — used per-message by `AssistantRoundView` to
//  resolve what to display when an assistant message shipped its answer via
//  the `final_answer` tool instead of plain content.
//
//  All pure: no SwiftUI, no IO. Tests can hit them directly.
//

import Foundation
import LLMCore
import LLMKit

// MARK: - Row groups

/// One renderable row in the chat timeline. Consecutive assistant + tool
/// messages from a single agent turn collapse into one `assistantRound`,
/// so the user sees one logical AI reply per question instead of N bubbles.
enum MessageGroup: Identifiable {
    case user(ChatMessageContent)
    case assistantRound(id: String, messages: [ChatMessage])
    case loading(UUID)
    case error(UUID, String)

    var id: String {
        switch self {
            case .user(let c): return c.id
            case .assistantRound(let id, _): return id
            case .loading(let id): return id.uuidString
            case .error(let id, _): return id.uuidString
        }
    }
}

/// Snapshot used by `AIChatView` to drive the list. `staticGroups` are committed
/// rows that don't change; `liveStream` (if any) feeds the in-flight assistant
/// round, with `liveCommittedRound` being the messages of that round that *have*
/// already landed in `conversation.messages`.
struct RowLayout {
    let staticGroups: [MessageGroup]
    let liveStream: LLMStreamingStateObject?
    let liveCommittedRound: [ChatMessage]
}

/// Walk the message list and bucket it into [user | assistantRound | loading | error].
/// system/developer messages are scaffolding and dropped here.
func groupMessages(_ messages: [ChatMessage]) -> [MessageGroup] {
    var result: [MessageGroup] = []
    var pending: [ChatMessage] = []

    func flushPending() {
        guard !pending.isEmpty else { return }
        result.append(.assistantRound(id: pending.last!.id, messages: pending))
        pending = []
    }

    for message in messages {
        switch message {
            case .content(let c):
                switch c.role {
                    case .user:
                        flushPending()
                        result.append(.user(c))
                    case .assistant, .tool:
                        pending.append(message)
                    case .system, .developer:
                        continue
                }
            case .loading(let id):
                flushPending()
                result.append(.loading(id))
            case .error(let id, let msg):
                flushPending()
                result.append(.error(id, msg))
        }
    }
    flushPending()
    return result
}

// MARK: - final_answer args parsing

/// Pull the user-facing text out of `final_answer`'s JSON arguments.
/// Tries the strict parse first; falls back to a lenient scan so partial args
/// (mid-stream) still yield readable text.
func parseFinalAnswerArgs(_ arguments: String) -> String {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidateKeys = ["text", "answer", "content", "final_answer", "result", "message", "response"]

    if let data = trimmed.data(using: .utf8) {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in candidateKeys {
                if let value = dict[key] as? String { return value }
            }
        }
        if let plain = try? JSONDecoder().decode(String.self, from: data) {
            return plain
        }
    }
    for key in candidateKeys {
        if let value = lenientExtract(trimmed, key: key) {
            return value
        }
    }
    return arguments
}

/// Find `"key": "..."` and return the value, stopping at the first unescaped
/// `"` or end-of-string. Tolerates truncated JSON during streaming.
private func lenientExtract(_ s: String, key: String) -> String? {
    let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\""
    guard let range = s.range(of: pattern, options: .regularExpression) else { return nil }
    var i = range.upperBound
    var result = ""
    while i < s.endIndex {
        let c = s[i]
        if c == "\\" {
            i = s.index(after: i)
            guard i < s.endIndex else { break }
            switch s[i] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                default: result.append(s[i])
            }
            i = s.index(after: i)
            continue
        }
        if c == "\"" {
            return result
        }
        result.append(c)
        i = s.index(after: i)
    }
    // Stream truncated mid-value — return what we have so far.
    return result.isEmpty ? nil : result
}
