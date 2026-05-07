//
//  QueryLibraryItemTool.swift
//  ExcalidrawZ
//
//  Fetches a single library item by id within a given library and
//  returns the full record including the raw Excalidraw elements JSON.
//  Use this when you've already located the item via
//  `list_library_items` and now need its actual shape data — fetching
//  one record is cheaper than the whole library in `verbose=true` mode.
//

import Foundation
import CoreData
import LLMCore

struct QueryLibraryItemTool: Tool {
    var name: String { "query_library_item" }

    var displayName: String { "Query Library Item" }

    var description: String {
        """
        Get one library item's full record (including the raw Excalidraw \
        elements JSON) by id. Get item ids from `list_library_items`. \
        Use this to inspect a specific reusable shape's contents before \
        deciding how to compose with it.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "library_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the parent library."
                ),
                "item_id": ParameterProperty(
                    type: "string",
                    description: "Library item id (string, not UUID — Excalidraw item ids are arbitrary strings)."
                )
            ],
            required: ["library_id", "item_id"]
        ))
    }

    /// Returns the raw element payload of a single user-authored
    /// library item. That's the highest-fidelity content reveal of any
    /// of the library tools — always require explicit approval.
    var alwaysRequiresApproval: Bool { true }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = try parseInput(input)

        let ctx = PersistenceController.shared.newTaskContext()
        let payload: [String: Any] = try await ctx.perform {
            // Resolve library first — we want a clear "library not found"
            // vs "item not found in this library" distinction in errors.
            let libFetch = NSFetchRequest<Library>(entityName: "Library")
            libFetch.predicate = NSPredicate(format: "id == %@", params.libraryID as CVarArg)
            libFetch.fetchLimit = 1
            guard let library = try ctx.fetch(libFetch).first else {
                throw ToolError.executionFailed("Library not found: \(params.libraryID)")
            }

            let itemFetch = NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
            itemFetch.predicate = NSPredicate(
                format: "library == %@ AND id == %@",
                library,
                params.itemID
            )
            itemFetch.fetchLimit = 1
            guard let item = try ctx.fetch(itemFetch).first else {
                throw ToolError.executionFailed(
                    "Item '\(params.itemID)' not found in library '\(params.libraryID)'."
                )
            }

            var dict: [String: Any] = [
                "library_id": params.libraryID,
                "library_name": library.name ?? "Untitled",
                "id": item.id ?? "",
                "rank": item.rank,
            ]
            if let name = item.name, !name.isEmpty {
                dict["name"] = name
            }
            if let status = item.status {
                dict["status"] = status
            }
            if let createdAt = item.createdAt {
                dict["created_at"] = ISO8601DateFormatter.shared.string(from: createdAt)
            }
            if let elements = Self.decodeElements(item.elements) {
                dict["elements"] = elements
            }
            return dict
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func decodeElements(_ data: Data?) -> Any? {
        guard let data, !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return value
    }

    // MARK: - Input

    private struct Params {
        var libraryID: String
        var itemID: String
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `library_id` and `item_id`.")
        }
        guard let libraryID = json["library_id"] as? String, !libraryID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: library_id")
        }
        guard let itemID = json["item_id"] as? String, !itemID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: item_id")
        }
        return Params(libraryID: libraryID, itemID: itemID)
    }
}
