//
//  RenameFileTool.swift
//  ExcalidrawZ
//
//  Created by Coding Assistant on 2026/5/8.
//

import Foundation
import CoreData
import LLMCore

struct RenameFileTool: Tool {
    struct RenameContext: ToolContext {
        var currentFileID: UUID?
    }

    var name: String { "rename_file" }

    var displayName: String { String(localizable: .aiChatToolRenameFileName) }

    var description: String {
        """
        Rename a drawing file in the user's iCloud-synced library. If \
        `file_id` is omitted, this renames the currently open iCloud file. \
        Use `list_all_files` first when the user wants to rename a different \
        library file. Pass the visible filename without the `.excalidraw` \
        extension.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "new_name": ParameterProperty(
                    type: "string",
                    description: "New visible filename, without `.excalidraw`."
                ),
                "file_id": ParameterProperty(
                    type: "string",
                    description: "Optional UUID of the file from `list_all_files`. If omitted, uses the current iCloud file."
                )
            ],
            required: ["new_name"]
        ))
    }

    /// Renaming changes the user's library organization, so require an
    /// explicit approval before execution.
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = try parseInput(input)
        let fileID = try resolveFileID(params.fileID, context: context)

        let ctx = PersistenceController.shared.newTaskContext()
        let output: Output = try await ctx.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "id == %@", fileID as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let file = try ctx.fetch(fetchRequest).first else {
                throw ToolError.executionFailed("File not found: \(fileID.uuidString)")
            }

            let oldName = file.name ?? "Untitled"
            file.name = params.newName
            file.updatedAt = Date()
            try ctx.save()

            return Output(
                fileID: fileID.uuidString,
                oldName: oldName,
                newName: params.newName
            )
        }

        let data = try JSONEncoder().encode(output)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func resolveFileID(_ explicitFileID: UUID?, context: (any ChatInvocationContext)?) throws -> UUID {
        if let explicitFileID {
            return explicitFileID
        }

        guard let context else {
            throw ToolError.invalidInput("Missing file_id and no current file context is available.")
        }

        let renameContext = try context.resolve(RenameContext.self)
        guard let currentFileID = renameContext.currentFileID else {
            throw ToolError.invalidInput("Missing file_id. The current file is not an iCloud library file.")
        }
        return currentFileID
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `new_name`.")
        }

        guard let rawName = json["new_name"] as? String else {
            throw ToolError.invalidInput("Missing required parameter: new_name")
        }

        let newName = sanitizedName(rawName)
        guard !newName.isEmpty else {
            throw ToolError.invalidInput("new_name cannot be empty.")
        }

        let fileID: UUID? = {
            guard let rawFileID = json["file_id"] as? String, !rawFileID.isEmpty else { return nil }
            return UUID(uuidString: rawFileID)
        }()

        if (json["file_id"] as? String)?.isEmpty == false, fileID == nil {
            throw ToolError.invalidInput("file_id must be a valid UUID.")
        }

        return Params(fileID: fileID, newName: newName)
    }

    private func sanitizedName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".excalidraw") {
            name.removeLast(".excalidraw".count)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    private struct Params {
        let fileID: UUID?
        let newName: String
    }

    private struct Output: Encodable {
        let fileID: String
        let oldName: String
        let newName: String

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case oldName = "old_name"
            case newName = "new_name"
        }
    }
}
