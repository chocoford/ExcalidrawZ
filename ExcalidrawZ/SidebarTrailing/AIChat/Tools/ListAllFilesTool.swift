//
//  ListAllFilesTool.swift
//  ExcalidrawZ
//
//  Lists all available drawing files in the user's library so the AI can
//  pick a target for follow-up tools (`query_file_history`,
//  `restore_file_history`, etc.). Scope: database `File` entities only —
//  iCloud-synced library, not local-folder URLs or temporary files.
//  Local files are URL-keyed so they need a separate tool (or a unified
//  surface with a `type` discriminator); we punt on that until the
//  AI's actually asking for it.
//

import Foundation
import CoreData
import LLMCore

struct ListAllFilesTool: Tool {
    var name: String { "list_all_files" }

    var displayName: String { "List Files" }

    var description: String {
        """
        List all available drawing files in the user's library (iCloud-synced \
        files only — local-folder files aren't included). Each entry returns \
        id, name, group, last-modified, and trash status. Use this to pick a \
        file id for `query_file_history` / `restore_file_history`.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "include_trashed": ParameterProperty(
                    type: "boolean",
                    description: "Include files in trash. Default: false."
                ),
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Max items to return, capped server-side at 200. Default: 100."
                )
            ],
            required: []
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = parseInput(input)
        let limit = min(max(params.limit, 1), 200)

        let context = PersistenceController.shared.newTaskContext()
        let entries: [FileEntry] = try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            if !params.includeTrashed {
                fetchRequest.predicate = NSPredicate(format: "inTrash == NO OR inTrash == nil")
            }
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            fetchRequest.fetchLimit = limit

            let files = try context.fetch(fetchRequest)
            return files.map { f in
                FileEntry(
                    id: f.id?.uuidString ?? "",
                    name: f.name ?? "Untitled",
                    group: f.group?.name,
                    updatedAt: f.updatedAt.map(ISO8601DateFormatter.shared.string(from:)),
                    inTrash: f.inTrash
                )
            }
        }

        let payload = Output(
            files: entries,
            returned: entries.count,
            limit: limit
        )
        let data = try JSONEncoder().encode(payload)
        return .text(String(data: data, encoding: .utf8) ?? "[]")
    }

    // MARK: - Input

    private struct Params {
        var includeTrashed: Bool
        var limit: Int
    }

    private func parseInput(_ input: String) -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Params(includeTrashed: false, limit: 100)
        }
        return Params(
            includeTrashed: json["include_trashed"] as? Bool ?? false,
            limit: (json["limit"] as? Int) ?? 100
        )
    }

    // MARK: - Output

    private struct Output: Encodable {
        let files: [FileEntry]
        let returned: Int
        let limit: Int
    }

    private struct FileEntry: Encodable {
        let id: String
        let name: String
        let group: String?
        let updatedAt: String?
        let inTrash: Bool
    }
}

// Shared formatter so tools don't each spin up their own. ISO8601 is what
// LLMs handle most reliably across providers — drop locale/timezone
// ambiguity entirely.
extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
