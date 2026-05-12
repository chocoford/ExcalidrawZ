//
//  QueryFileHistoryTool.swift
//  ExcalidrawZ
//
//  Lists checkpoint history for a given file. Each entry surfaces the
//  AI-history fields (`source`, `messageID`, `historyDescription`) so
//  the AI / UI can present "revert to this point" affordances and
//  understand which checkpoints were AI-generated vs user edits.
//
//  Scope: database `File` entities. Local files (LocalFileCheckpoint)
//  are URL-keyed and would need a separate tool surface — punt until
//  the AI asks for it.
//

import Foundation
import CoreData
import LLMCore

struct QueryFileHistoryTool: Tool {
    var name: String { "query_file_history" }

    var displayName: String { String(localizable: .aiChatToolQueryFileHistoryName) }

    var description: String {
        """
        List the checkpoint history of a drawing file. Each entry returns \
        checkpoint id, source ("user" / "ai_pre" / "ai_post"), the chat \
        message id it's anchored to (if any), an optional description, \
        and the timestamp. Use this to find a checkpoint id for \
        `restore_file_history`. Get file ids from `list_all_files`.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "file_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the file (from `list_all_files`)."
                ),
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Max checkpoints to return, capped at 200. Default: 50, ordered most-recent first."
                ),
                "ai_only": ParameterProperty(
                    type: "boolean",
                    description: "If true, only return AI-generated checkpoints (`ai_pre` / `ai_post`). Default: false."
                )
            ],
            required: ["file_id"]
        ))
    }

    /// Reading a file's checkpoint history exposes when it was edited
    /// and which edits came from prior AI rounds — both pieces of user
    /// data that the user should explicitly authorize before the AI
    /// pulls them into the chat.
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = try parseInput(input)
        let limit = min(max(params.limit, 1), 200)

        let ctx = PersistenceController.shared.newTaskContext()
        let payload: Output = try await ctx.perform {
            // Resolve the file by UUID.
            let fileFetch = NSFetchRequest<File>(entityName: "File")
            fileFetch.predicate = NSPredicate(format: "id == %@", params.fileID as CVarArg)
            fileFetch.fetchLimit = 1
            guard let file = try ctx.fetch(fileFetch).first else {
                throw ToolError.executionFailed("File not found: \(params.fileID)")
            }

            // Fetch checkpoints.
            let cpFetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            if params.aiOnly {
                cpFetch.predicate = NSPredicate(
                    format: "file == %@ AND (source == %@ OR source == %@)",
                    file,
                    FileCheckpointSource.aiPre.rawValue,
                    FileCheckpointSource.aiPost.rawValue
                )
            } else {
                cpFetch.predicate = NSPredicate(format: "file == %@", file)
            }
            cpFetch.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            cpFetch.fetchLimit = limit

            let checkpoints = try ctx.fetch(cpFetch)
            let entries = checkpoints.map { cp in
                CheckpointEntry(
                    id: cp.id?.uuidString ?? "",
                    source: cp.checkpointSource.rawValue,
                    messageID: cp.messageID,
                    description: cp.historyDescription,
                    updatedAt: cp.updatedAt.map(ISO8601DateFormatter.shared.string(from:)),
                    contentSize: cp.content?.count ?? 0
                )
            }

            return Output(
                fileID: params.fileID,
                fileName: file.name ?? "Untitled",
                history: entries,
                returned: entries.count,
                limit: limit
            )
        }

        let data = try JSONEncoder().encode(payload)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: - Input

    private struct Params {
        var fileID: String
        var limit: Int
        var aiOnly: Bool
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `file_id`.")
        }
        guard let fileID = json["file_id"] as? String, !fileID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: file_id")
        }
        return Params(
            fileID: fileID,
            limit: (json["limit"] as? Int) ?? 50,
            aiOnly: (json["ai_only"] as? Bool) ?? false
        )
    }

    // MARK: - Output

    private struct Output: Encodable {
        let fileID: String
        let fileName: String
        let history: [CheckpointEntry]
        let returned: Int
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case fileName = "file_name"
            case history
            case returned
            case limit
        }
    }

    private struct CheckpointEntry: Encodable {
        let id: String
        let source: String
        let messageID: String?
        let description: String?
        let updatedAt: String?
        let contentSize: Int

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case messageID = "message_id"
            case description
            case updatedAt = "updated_at"
            case contentSize = "content_size"
        }
    }
}
