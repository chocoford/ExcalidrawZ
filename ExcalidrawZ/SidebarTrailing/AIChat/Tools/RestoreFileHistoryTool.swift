//
//  RestoreFileHistoryTool.swift
//  ExcalidrawZ
//
//  Restores a file to a specific checkpoint snapshot.
//
//  - Looks up the file + checkpoint by UUID.
//  - Loads checkpoint content (iCloud Drive path or fallback to Core Data).
//  - Writes content back to the file (Core Data + iCloud Drive storage).
//  - If the restored file is the currently active file in the canvas,
//    triggers a coordinator reload so the user sees the change immediately.
//
//  Phase 4 will add a UI approval gate around this — destructive op, user
//  needs to explicitly OK. For now, executes without prompt; the caller
//  (the AI) is expected to confirm with the user via chat first.
//

import Foundation
import CoreData
import LLMCore

struct RestoreFileHistoryTool: Tool {
    /// Optional context. When present we use `canvasTarget` to refresh the
    /// canvas if the restored file is currently active. Without it, the
    /// restore still writes correctly — the user just won't see the
    /// change until they re-open the file.
    struct RestoreContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    }

    var name: String { "restore_file_history" }

    var displayName: String { String(localizable: .aiChatToolRestoreFileHistoryName) }

    var description: String {
        """
        Restore a drawing file to a specific checkpoint. The file's current \
        content is OVERWRITTEN with the checkpoint's content. This is \
        destructive — confirm with the user in chat before calling. Get \
        valid (file_id, checkpoint_id) pairs from `query_file_history`.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "file_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the file to restore."
                ),
                "checkpoint_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the checkpoint to restore from. Must belong to file_id."
                )
            ],
            required: ["file_id", "checkpoint_id"]
        ))
    }

    /// Restores overwrite the file's current content — always require user
    /// approval before executing. The user can opt to "always allow" within
    /// the conversation, in which case subsequent restores within the same
    /// conversation skip the prompt (LLMKit caches the decision).
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let params = try parseInput(input)

        let coreData = PersistenceController.shared
        let resolveCtx = coreData.newTaskContext()

        // 1. Resolve file + checkpoint object IDs, sanity-check the
        //    relationship (don't restore a checkpoint from file A onto
        //    file B — would be a silent corruption).
        let resolution: Resolution = try await resolveCtx.perform {
            let fileFetch = NSFetchRequest<File>(entityName: "File")
            fileFetch.predicate = NSPredicate(format: "id == %@", params.fileID as CVarArg)
            fileFetch.fetchLimit = 1
            guard let file = try resolveCtx.fetch(fileFetch).first else {
                throw ToolError.executionFailed("File not found: \(params.fileID)")
            }

            let cpFetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            cpFetch.predicate = NSPredicate(format: "id == %@", params.checkpointID as CVarArg)
            cpFetch.fetchLimit = 1
            guard let checkpoint = try resolveCtx.fetch(cpFetch).first else {
                throw ToolError.executionFailed("Checkpoint not found: \(params.checkpointID)")
            }
            guard checkpoint.file?.objectID == file.objectID else {
                throw ToolError.executionFailed(
                    "Checkpoint \(params.checkpointID) doesn't belong to file \(params.fileID)."
                )
            }
            return Resolution(
                fileObjectID: file.objectID,
                checkpointObjectID: checkpoint.objectID,
                fileName: file.name ?? "Untitled",
                checkpointSource: checkpoint.checkpointSource.rawValue,
                checkpointUpdatedAt: checkpoint.updatedAt
            )
        }

        // 2. Run the actual restore through the existing repository
        //    method. It updates Core Data; storage save is on us.
        try await coreData.checkpointRepository.restoreCheckpoint(
            checkpointObjectID: resolution.checkpointObjectID,
            to: resolution.fileObjectID
        )
        try await coreData.fileRepository.saveFileContentToStorage(
            fileObjectID: resolution.fileObjectID,
            content: try await coreData.checkpointRepository.loadCheckpointContent(
                checkpointObjectID: resolution.checkpointObjectID
            )
        )

        // 3. If we have a canvas context AND the restored file matches
        //    the canvas's current file, force a reload so the user sees
        //    the change without remounting. If context is missing or
        //    the file isn't currently displayed, the next file load
        //    will pick up the new content naturally.
        if let context,
           let restoreContext = try? context.resolve(RestoreContext.self) {
            await reloadCanvasIfActive(
                fileObjectID: resolution.fileObjectID,
                canvasTarget: restoreContext.canvasTarget
            )
        }

        let timestampString = resolution.checkpointUpdatedAt
            .map(ISO8601DateFormatter.shared.string(from:)) ?? "unknown"
        return .text(
            "Restored file '\(resolution.fileName)' to checkpoint " +
            "(\(resolution.checkpointSource), \(timestampString))."
        )
    }

    // MARK: - Helpers

    private struct Params {
        var fileID: String
        var checkpointID: String
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `file_id` and `checkpoint_id`.")
        }
        guard let fileID = json["file_id"] as? String, !fileID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: file_id")
        }
        guard let checkpointID = json["checkpoint_id"] as? String, !checkpointID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: checkpoint_id")
        }
        return Params(fileID: fileID, checkpointID: checkpointID)
    }

    private struct Resolution {
        let fileObjectID: NSManagedObjectID
        let checkpointObjectID: NSManagedObjectID
        let fileName: String
        let checkpointSource: String
        let checkpointUpdatedAt: Date?
    }

    /// Reload the canvas only if the restored file is currently active.
    /// We bridge through `ExcalidrawCoordinatorRegistry.shared.coordinator(for:)`
    /// instead of going through `FileState` because tools don't have a
    /// fileState reference — the registry is the singleton seam built
    /// for this kind of cross-thread access.
    @MainActor
    private func reloadCanvasIfActive(
        fileObjectID: NSManagedObjectID,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async {
        guard let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget) else {
            return
        }
        let viewContext = PersistenceController.shared.container.viewContext
        guard let restoredFile = try? viewContext.existingObject(with: fileObjectID) as? File else {
            return
        }
        // `loadFile(from:force:)` is the same call site `FileCheckpointDetailView`
        // uses for the post-restore canvas refresh — guarantees behavioural
        // parity with the existing UI restore path.
        await coordinator.loadFile(from: restoredFile, force: true)
    }
}
