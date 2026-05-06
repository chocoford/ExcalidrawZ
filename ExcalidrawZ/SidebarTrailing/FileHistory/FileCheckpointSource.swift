//
//  FileCheckpointSource.swift
//  ExcalidrawZ
//
//  Typed enum for the new `source` field on `FileCheckpoint` /
//  `LocalFileCheckpoint`. Lets callers branch on semantic intent without
//  scattering string literals.
//
//  Schema-level fields (auto-generated on both Core Data entities):
//    - `source`              — raw string, one of `FileCheckpointSource.rawValue` or nil (legacy)
//    - `messageID`           — chat message id this checkpoint anchors to (nil for plain user edits)
//    - `historyDescription`  — git-style summary, AI fills in for ai_post, user can edit later
//

import Foundation

/// Why a checkpoint exists. `nil` raw value (legacy rows) is treated as `.user`.
enum FileCheckpointSource: String {
    /// Plain user edit — the historical default. Recorded by `FileRepository`'s
    /// "first edit creates, subsequent edits update latest" rule.
    case user = "user"

    /// Snapshot taken right *before* a user message hits the AI. The state
    /// you'd want to revert to if the AI's changes turn out wrong. Anchored
    /// to the user `messageID`.
    case aiPre = "ai_pre"

    /// Snapshot taken right *after* an AI turn finishes successfully.
    /// Anchored to the assistant's final-answer `messageID`.
    case aiPost = "ai_post"
}

extension FileCheckpointRepresentable {
    /// Resolved source — `nil` raw → `.user`, unknown raw → `.user` (defensive).
    var checkpointSource: FileCheckpointSource {
        guard let raw = source, let parsed = FileCheckpointSource(rawValue: raw) else {
            return .user
        }
        return parsed
    }

    /// Whether this checkpoint was created by the AI integration (either
    /// pre or post).
    var isAIGenerated: Bool {
        switch checkpointSource {
            case .user: return false
            case .aiPre, .aiPost: return true
        }
    }
}
