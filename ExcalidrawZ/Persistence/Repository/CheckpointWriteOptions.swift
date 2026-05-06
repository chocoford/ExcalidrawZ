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
//  - `userEdit`     — historical user-edit semantics: first edit creates a
//                     fresh user checkpoint, subsequent edits within the
//                     same session update the latest user row. AI-tagged
//                     rows are skipped over (immutable snapshots).
//  - `explicit`     — force-create a checkpoint with explicit metadata.
//                     Used by the AI chat session begin/end hooks.
//

import Foundation

enum CheckpointWriteOptions {
    case suppress
    case userEdit(newCheckpoint: Bool)
    case explicit(
        source: FileCheckpointSource,
        messageID: String?,
        description: String?
    )
}
