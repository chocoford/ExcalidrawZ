//
//  ListLibraryItemsTool.swift
//  ExcalidrawZ
//
//  Lists items inside a given `Library`. Filters and detail-level are
//  configurable so the AI can:
//  - Skim ids+names cheaply (default `verbose=false`)
//  - Pull a windowed slice via `start_index` / `end_index`
//  - Filter to only named items (skip the unnamed scratch shapes)
//  - Pull the raw Excalidraw element JSON (verbose mode)
//
//  Use `query_library_item` when you only need one specific item — that
//  avoids returning the entire library's elements payload.
//

import Foundation
import CoreData
import LLMCore

struct ListLibraryItemsTool: Tool {
    var name: String { "list_library_items" }

    var displayName: String { "List Library Items" }

    var description: String {
        """
        List items inside a library. Get library_ids from `list_libraries`. \
        Items are ordered by rank (the user's shelf order). Filters: \
        `named_only=true` skips items without a name; `start_index` / \
        `end_index` slice a window. `verbose=true` includes the raw \
        Excalidraw elements JSON (heavy — only use when you need the \
        actual shape data); default `false` returns just id, name, rank, \
        and basic metadata.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "library_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the library (from `list_libraries`)."
                ),
                "named_only": ParameterProperty(
                    type: "boolean",
                    description: "If true, only return items that have a non-empty name. Default: false."
                ),
                "start_index": ParameterProperty(
                    type: "integer",
                    description: "Inclusive starting index in the rank-ordered list. Default: 0."
                ),
                "end_index": ParameterProperty(
                    type: "integer",
                    description: "Exclusive end index. Default: include everything from start_index onward."
                ),
                "verbose": ParameterProperty(
                    type: "boolean",
                    description: "If true, include the raw Excalidraw elements JSON for each item (heavy). Default: false (returns id+name+rank+status+createdAt only)."
                )
            ],
            required: ["library_id"]
        ))
    }

    /// Listing the items inside a user library — especially with
    /// `verbose=true` returning raw element JSON — pulls user-authored
    /// content into the chat. Gate on explicit approval.
    var alwaysRequiresApproval: Bool { true }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = try parseInput(input)

        let ctx = PersistenceController.shared.newTaskContext()
        let payload: [String: Any] = try await ctx.perform {
            // Resolve library by id (UUID string).
            let libFetch = NSFetchRequest<Library>(entityName: "Library")
            libFetch.predicate = NSPredicate(format: "id == %@", params.libraryID as CVarArg)
            libFetch.fetchLimit = 1
            guard let library = try ctx.fetch(libFetch).first else {
                throw ToolError.executionFailed("Library not found: \(params.libraryID)")
            }

            // Items are toMany on Library; fetch via the relationship and
            // sort by rank. NSFetchRequest with predicate is more flexible
            // than relying on the ordered relationship default.
            let itemFetch = NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
            var predicates: [NSPredicate] = [NSPredicate(format: "library == %@", library)]
            if params.namedOnly {
                predicates.append(NSPredicate(format: "name != nil AND name != %@", ""))
            }
            itemFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            itemFetch.sortDescriptors = [
                NSSortDescriptor(key: "rank", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]

            var items = try ctx.fetch(itemFetch)
            let totalMatching = items.count

            // Window into the sorted list. Clamp indices defensively —
            // the LLM can pass nonsense and we'd rather return an empty
            // slice than crash.
            let lower = max(0, params.startIndex ?? 0)
            let upper = min(items.count, params.endIndex ?? items.count)
            if lower < upper {
                items = Array(items[lower..<upper])
            } else {
                items = []
            }

            let entries: [[String: Any]] = items.map { item in
                Self.serialize(item: item, verbose: params.verbose)
            }

            return [
                "library_id": params.libraryID,
                "library_name": library.name ?? "Untitled",
                "items": entries,
                "returned": entries.count,
                "total_matching": totalMatching,
                "start_index": lower,
                "end_index": upper,
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    /// Build the per-item dict. `verbose` toggles between metadata-only
    /// (cheap; what `named_only` slicing usually wants) and full elements
    /// JSON (heavy; used when the AI needs to inspect actual shapes).
    private static func serialize(item: LibraryItem, verbose: Bool) -> [String: Any] {
        var dict: [String: Any] = [
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
        if verbose, let elements = decodeElements(item.elements) {
            dict["elements"] = elements
        }
        return dict
    }

    /// Decode the raw `elements` blob as a JSON value. Returns nil when
    /// the blob is missing or unparseable — we'd rather report "no
    /// elements" than throw out the whole batch over one bad row.
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
        var namedOnly: Bool
        var startIndex: Int?
        var endIndex: Int?
        var verbose: Bool
    }

    private func parseInput(_ input: String) throws -> Params {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidInput("Expected JSON object with `library_id`.")
        }
        guard let libraryID = json["library_id"] as? String, !libraryID.isEmpty else {
            throw ToolError.invalidInput("Missing required parameter: library_id")
        }
        return Params(
            libraryID: libraryID,
            namedOnly: (json["named_only"] as? Bool) ?? false,
            startIndex: json["start_index"] as? Int,
            endIndex: json["end_index"] as? Int,
            verbose: (json["verbose"] as? Bool) ?? false
        )
    }
}
