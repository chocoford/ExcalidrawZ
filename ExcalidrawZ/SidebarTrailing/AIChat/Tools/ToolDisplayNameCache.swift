//
//  ToolDisplayNameCache.swift
//  ExcalidrawZ
//
//  Sync-accessible mapping from a tool's machine `name` (snake_case,
//  what the LLM emits in `tool_calls`) to its UI `displayName`. SwiftUI
//  body code can't `await` into the `LLMStateObject.toolRegistry` actor
//  to pull a tool's displayName, so we mirror the mapping here at app
//  init time.
//
//  Single-writer (App init), many readers (ToolCallCard / approval UI
//  fallbacks). `@MainActor` because every reader is a SwiftUI view body.
//

import Foundation
import LLMCore

@MainActor
enum ToolDisplayNameCache {
    private static var map: [String: String] = [:]

    /// Snapshot the `name → displayName` mapping for the supplied tools.
    /// Call this BEFORE the async `toolRegistry.register([...])` Task so
    /// the cache is ready by the time any UI mounts.
    static func register(_ tools: [Tool]) {
        for tool in tools {
            map[tool.name] = tool.displayName
        }
    }

    /// Look up a friendly name. Falls back to the snake_case machine name
    /// if the tool isn't registered (third-party / forgotten override) so
    /// the UI never shows an empty string — just unfriendly text.
    static func displayName(for toolName: String) -> String {
        map[toolName] ?? toolName
    }
}
