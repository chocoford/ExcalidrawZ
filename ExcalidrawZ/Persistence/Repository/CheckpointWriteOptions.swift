//
//  CheckpointWriteOptions.swift
//  ExcalidrawZ
//
//  Policy enum that callers of `FileRepository.updateElements(...)` and the
//  local-file equivalent use to control checkpoint history behaviour.
//
//  - `suppress`     — content saves; NO checkpoint row touched. Used while
//                     an AI chat session is active so canvas mutations
//                     don't pollute user history.
//  - `userEdit`     — user-edit semantics: first edit creates a fresh user
//                     checkpoint, subsequent edits update the latest user row
//                     until the rollover interval passes. AI-tagged rows are
//                     skipped over (immutable snapshots).
//  - `explicit`     — force-create a checkpoint with explicit metadata.
//                     Used by the AI chat session begin/end hooks.
//

import Foundation

enum CheckpointWriteOptions {
    case suppress
    case userEdit(newCheckpoint: Bool)
    case explicit(
        source: FileCheckpointSource,
        description: String?
    )
}

enum UserCheckpointRolloverPolicy {
    static let interval: TimeInterval = 10 * 60

    /// Checkpoint windows belong to the current editor session. Their start
    /// time is deliberately kept in memory so reopening a document begins a
    /// fresh history segment while `updatedAt` retains its normal meaning.
    static func shouldStartNewWindow(
        startedAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard let startedAt else {
            return true
        }
        return now.timeIntervalSince(startedAt) >= interval
    }
}
