//
//  ExcalidrawAgentConfig.swift
//  ExcalidrawZ
//
//  Single source of truth for ExcalidrawZ's chat agent wiring.
//
//  This app's chat is **not user-selectable**: every conversation runs
//  against the `excalidraw-canvas` server-side agent with the same
//  fixed local tool roster. We keep that wiring here so both paths
//  agree:
//
//  - `PromptInputView.startSend` calls `defaultConfig()` when minting a
//    fresh conversation.
//  - `LLMPersistenceProvider` calls `defaultConfig()` when restoring
//    conversations from Core Data — the conversation's `agentConfig` is
//    intentionally NOT persisted, so a restore picks up whatever the
//    current binary's tool roster is. New tools are then immediately
//    available to old conversations on regenerate, which is what we
//    want as the app evolves.
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
        "read_file",
        "read_canvas_image",
        "calculator",
        "datetime",
        "adjust_elements",
        "rename_file",
        "list_all_files",
        "query_file_history",
        "restore_file_history",
        "list_libraries",
        "list_library_items",
        "query_library_item",
        "add_library_item_to_canvas",
        "final_answer"
    ]

    /// Build the `AgentConfig` used by every chat conversation in this
    /// app. Centralized so the create-conversation path and the
    /// restore-conversation path can't drift.
    static func defaultConfig() -> AgentConfig {
        .withTools(toolNames, agentID: agentID)
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
        "adjust_elements",
        "add_library_item_to_canvas",
        "restore_file_history",
    ]
}
