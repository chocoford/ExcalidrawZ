//
//  ListLibrariesTool.swift
//  ExcalidrawZ
//
//  Lists all `Library` collections in the user's library shelf. Returns
//  metadata only — no item contents. Use `list_library_items` for per-
//  library items, and `query_library_item` to look up one item's full
//  element JSON.
//

import Foundation
import CoreData
import LLMCore

struct ListLibrariesTool: Tool {
    var name: String { "list_libraries" }

    var displayName: String { String(localizable: .aiChatToolListLibrariesName) }

    var description: String {
        """
        List all available libraries (collections of reusable Excalidraw \
        shapes) in the user's library shelf. Returns id, name, item count, \
        and creation time per library. Use `list_library_items` to see \
        what's inside one.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "limit": ParameterProperty(
                    type: "integer",
                    description: "Max items to return, capped server-side at 200. Default: 100."
                )
            ],
            required: []
        ))
    }

    /// Library shelves are user-curated content; surveying what's
    /// available is a privacy-relevant readout. Always require approval
    /// before exposing it to the model.
    var approvalRequirement: ApprovalRequirement { .always }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        let limit = parseLimit(input)

        let ctx = PersistenceController.shared.newTaskContext()
        let entries: [LibraryEntry] = try await ctx.perform {
            let fetch = NSFetchRequest<Library>(entityName: "Library")
            // Library order matches the user's shelf order — by rank
            // first, then created-at as tiebreaker.
            fetch.sortDescriptors = [
                NSSortDescriptor(key: "rank", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]
            fetch.fetchLimit = limit

            let libraries = try ctx.fetch(fetch)
            return libraries.map { lib in
                LibraryEntry(
                    id: lib.id?.uuidString ?? "",
                    name: lib.name ?? "Untitled",
                    itemsCount: lib.items?.count ?? 0,
                    createdAt: lib.createdAt.map(ISO8601DateFormatter.shared.string(from:))
                )
            }
        }

        let payload = Output(libraries: entries, returned: entries.count)
        let data = try JSONEncoder().encode(payload)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func parseLimit(_ input: String) -> Int {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limit = json["limit"] as? Int else {
            return 100
        }
        return min(max(limit, 1), 200)
    }

    private struct Output: Encodable {
        let libraries: [LibraryEntry]
        let returned: Int
    }

    private struct LibraryEntry: Encodable {
        let id: String
        let name: String
        let itemsCount: Int
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case itemsCount = "items_count"
            case createdAt = "created_at"
        }
    }
}
