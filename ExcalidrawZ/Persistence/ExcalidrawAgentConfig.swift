//
//  ExcalidrawAgentConfig.swift
//  ExcalidrawZ
//
//  Single source of truth for ExcalidrawZ's chat agent wiring.
//
//  Every conversation runs against the `excalidraw-canvas` server-side
//  agent, while the local tool roster is selected by chat mode. The
//  baseline rosters live here, and model capability filters derive
//  from the same list so create/send/restore can't drift:
//
//  - `PromptInputView.startSend` calls `defaultConfig()` when minting a
//    fresh conversation.
//  - `LLMPersistenceProvider` calls `defaultConfig(tools:)` when
//    restoring conversations from Core Data. The tool roster can be
//    conversation-specific (for example, filtered by model image-input
//    capability), while agentID and defaults remain centralized here.
//
//  When/if we ever want per-conversation overrides (e.g. user picks a
//  light/heavy tool set), this becomes the migration point: add a
//  parameter, persist the difference, keep this default as the floor.
//

import Foundation
import LLMCore

enum ExcalidrawAgentConfig {
    /// Server-side domain agent identifier. The backend resolves system
    /// prompt + allowed-model whitelist from this; the client only
    /// supplies the tool roster.
    static let agentID = "excalidraw-canvas"

    /// Full tool roster the chat agent is allowed to call. Order is
    /// not semantically meaningful to the LLM (it sees them as a set);
    /// it's just the ordering used in approval prompts and any UI hints.
    /// Names must match `Tool.name` of the registered implementations.
    static let toolNames: [String] = [
        "web_search",
        "web_fetch",
        "get_current_file",
        "read_file",
        "read_canvas_image",
        "export",
        "insert_math",
        "calculator",
        "datetime",
        "adjust_elements",
        "navigate_canvas",
        "set_canvas_preferences",
        "rename_file",
        "list_groups",
        "list_all_files",
        "list_local_folders",
        "list_local_files",
        "query_file_history",
        "restore_file_history",
        "list_libraries",
        "list_library_items",
        "query_library_item",
        "add_library_item_to_canvas"
    ]

    static let askToolNames: [String] = [
        "web_search",
        "web_fetch",
        "get_current_file",
        "read_file",
        "read_canvas_image",
        "export",
        "insert_math",
        "calculator",
        "datetime",
        "adjust_elements",
        "navigate_canvas",
        "list_groups",
        "list_local_folders",
        "list_local_files"
    ]

    /// Locked or user-disabled file access keeps real ExcalidrawZ files
    /// out of the tool surface. Proposal-writing remains available, but
    /// file-reading tools are intentionally removed so the model does
    /// not interpret protected content as an empty canvas.
    static let limitedFileAccessToolNames: [String] = [
        "web_search",
        "web_fetch",
        "file_access_status",
        "get_current_file",
        "navigate_canvas",
        "insert_math",
        "calculator",
        "datetime",
        "adjust_elements"
    ]

    static func toolNames(supportsImageInput: Bool) -> [String] {
        guard supportsImageInput else {
            return toolNames.filter { $0 != "read_canvas_image" }
        }
        return toolNames
    }

    static func toolNames(
        mode: AIChatInteractionMode,
        supportsImageInput: Bool,
        includesCurrentFileContext: Bool
    ) -> [String] {
        let baseTools: [String] = switch mode {
            case .agent:
                includesCurrentFileContext ? toolNames : limitedFileAccessToolNames
            case .ask:
                includesCurrentFileContext ? askToolNames : limitedFileAccessToolNames
        }
        guard supportsImageInput else {
            return baseTools.filter { $0 != "read_canvas_image" }
        }
        return baseTools
    }

    /// Build the `AgentConfig` used by every chat conversation in this
    /// app. Centralized so the create-conversation path and the
    /// restore-conversation path can't drift.
    static func defaultConfig(supportsImageInput: Bool = true) -> AgentConfig {
        defaultConfig(tools: toolNames(supportsImageInput: supportsImageInput))
    }

    static func defaultConfig(
        mode: AIChatInteractionMode,
        supportsImageInput: Bool,
        includesCurrentFileContext: Bool
    ) -> AgentConfig {
        defaultConfig(
            tools: toolNames(
                mode: mode,
                supportsImageInput: supportsImageInput,
                includesCurrentFileContext: includesCurrentFileContext
            )
        )
    }

    static func defaultConfig(tools: [String]?) -> AgentConfig {
        .withTools(tools ?? toolNames, maxThoughts: 30, agentID: agentID)
    }

    static func encodeToolNames(_ tools: [String]) -> Data? {
        try? JSONEncoder().encode(tools)
    }

    static func decodeToolNames(_ data: Data?) -> [String]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    /// Tools whose execution mutates the canvas. Used by the AI chat
    /// session bookkeeping to decide whether to keep the pre/post
    /// checkpoint pair around the round — no canvas mutation means no
    /// reason to spend a history row, so the `.aiPre` written at the
    /// start of the round gets cleaned up and no `.aiPost` is taken.
    ///
    /// `restore_file_history` is included even though it's "restoring,
    /// not editing" — from the canvas's perspective the elements
    /// change, the user might want to revert that revert, etc.
    /// Keeping a pair around it stays consistent with every other
    /// canvas mutation.
    static let canvasModifyingToolNames: Set<String> = [
        "insert_math",
        "adjust_elements",
        "add_library_item_to_canvas",
        "restore_file_history",
    ]
}
