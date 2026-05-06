//
//  AddLibraryItemToCanvasTool.swift
//  ExcalidrawZ
//
//  Inserts a library item's elements onto the current canvas at a
//  user-specified position. Bridges the gap between
//  `query_library_item` (read-only inspection) and `adjust_elements`
//  (per-element add ops) — for "stamp this saved shape onto the
//  canvas at (x, y)" the AI no longer needs to write per-element add
//  ops by hand, which got verbose for items with many parts (arrows
//  + bound text + groups).
//
//  Two non-trivial bits of plumbing this tool handles internally:
//
//  1. **Translation**: library items are stored in their original
//     authoring coordinates. Caller specifies the target top-left of
//     the bounding box; we compute the offset and shift every
//     element's x/y. (Inner `points` for lines/arrows/freeDraw are
//     relative to each element's x/y, so they don't need adjusting.)
//
//  2. **ID regeneration**: library item ids are stable, so naively
//     calling `addElements` twice would create two elements sharing
//     ids — undefined behaviour in Excalidraw. We mint fresh UUIDs
//     for every element id AND for every group id, then walk the
//     JSON to remap all internal references (`containerId`,
//     `boundElements[*].id`, `startBinding.elementId`,
//     `endBinding.elementId`, `frameId`, `groupIds[*]`). External
//     references (pointing to canvas elements not in this item) are
//     left as-is — they were already broken in the library blob; we
//     don't try to "fix" them.
//

import Foundation
import CoreData
import LLMCore

struct AddLibraryItemToCanvasTool: Tool {
    struct AddContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    }

    var name: String { "add_library_item_to_canvas" }

    var displayName: String { "Insert Library Item" }

    var description: String {
        """
        Insert a library item's shapes onto the current canvas at a \
        specified position. Get (library_id, item_id) from \
        `list_library_items` / `query_library_item`. The item's \
        bounding box top-left lands at (x, y); use this to place \
        copies of saved reusable shapes without writing per-element \
        add ops in `adjust_elements`. Each call mints fresh ids, so \
        you can stamp the same item multiple times without collision.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(
            properties: [
                "library_id": ParameterProperty(
                    type: "string",
                    description: "UUID of the library."
                ),
                "item_id": ParameterProperty(
                    type: "string",
                    description: "Item id (string) within the library."
                ),
                "x": ParameterProperty(
                    type: "number",
                    description: "Target canvas x for the bounding-box top-left, in canvas coordinates. Defaults to 0."
                ),
                "y": ParameterProperty(
                    type: "number",
                    description: "Target canvas y for the bounding-box top-left. Defaults to 0."
                )
            ],
            required: ["library_id", "item_id"]
        ))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let params = try parseInput(input)
        guard let context else {
            throw ToolError.executionFailed("Missing canvas context — tool needs an active Excalidraw coordinator.")
        }
        let addContext = try context.resolve(AddContext.self)

        // 1. Load the item's elements blob.
        let elementsBlob = try await loadElementsBlob(
            libraryID: params.libraryID,
            itemID: params.itemID
        )

        // 2. Decode as raw JSON, transform (translate + remap ids),
        //    re-encode.
        let transformedData = try transformElements(
            blob: elementsBlob,
            target: (params.x, params.y)
        )

        // 3. Decode as [ExcalidrawElement] for the coordinator API
        //    (which is type-checked, not raw JSON).
        let decoder = JSONDecoder()
        let decodedElements = try decoder.decode([ExcalidrawElement].self, from: transformedData)

        // 4. Push to canvas.
        try await applyToCanvas(
            elements: decodedElements,
            canvasTarget: addContext.canvasTarget
        )

        // 5. Surface the new ids so the AI can chain follow-ups
        //    (`adjust_elements` updates / arrow bindings against the
        //    just-inserted shapes).
        let newIDs = decodedElements.map { $0.id }
        let response: [String: Any] = [
            "ok": true,
            "added_count": newIDs.count,
            "new_element_ids": newIDs
        ]
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: - Core Data lookup

    private func loadElementsBlob(libraryID: String, itemID: String) async throws -> Data {
        let ctx = PersistenceController.shared.newTaskContext()
        return try await ctx.perform {
            let libFetch = NSFetchRequest<Library>(entityName: "Library")
            libFetch.predicate = NSPredicate(format: "id == %@", libraryID as CVarArg)
            libFetch.fetchLimit = 1
            guard let library = try ctx.fetch(libFetch).first else {
                throw ToolError.executionFailed("Library not found: \(libraryID)")
            }
            let itemFetch = NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
            itemFetch.predicate = NSPredicate(
                format: "library == %@ AND id == %@",
                library, itemID
            )
            itemFetch.fetchLimit = 1
            guard let item = try ctx.fetch(itemFetch).first else {
                throw ToolError.executionFailed("Item '\(itemID)' not found in library.")
            }
            guard let blob = item.elements, !blob.isEmpty else {
                throw ToolError.executionFailed("Item '\(itemID)' has no elements.")
            }
            return blob
        }
    }

    // MARK: - JSON transform

    /// Apply (translate + id-regen) to the raw elements JSON. We work
    /// at the JSON-dict level rather than going through `ExcalidrawElement`
    /// because the enum's value-type variants make in-place mutation
    /// awkward (you'd reconstruct each shape variant by hand).
    private func transformElements(
        blob: Data,
        target: (x: Double?, y: Double?)
    ) throws -> Data {
        guard var elements = try JSONSerialization.jsonObject(with: blob) as? [[String: Any]],
              !elements.isEmpty else {
            throw ToolError.executionFailed("Library item elements blob isn't a JSON array.")
        }

        // 1. Translation offset — needed only if caller supplied at least
        //    one coordinate. If both are nil, we keep the original layout.
        let offset = computeOffset(elements: elements, target: target)

        // 2. Build id mapping: every element id → fresh UUID. Group ids
        //    are a separate identity space (multiple elements share
        //    them), so we collect those distinctly.
        var idMapping: [String: String] = [:]
        var groupIDMapping: [String: String] = [:]
        for element in elements {
            if let oldID = element["id"] as? String {
                idMapping[oldID] = idMapping[oldID] ?? UUID().uuidString
            }
            if let groupIDs = element["groupIds"] as? [String] {
                for gid in groupIDs {
                    groupIDMapping[gid] = groupIDMapping[gid] ?? UUID().uuidString
                }
            }
        }

        // 3. Apply offset + id remap.
        for i in elements.indices {
            elements[i] = remapIDs(
                in: elements[i],
                idMapping: idMapping,
                groupIDMapping: groupIDMapping
            )
            if let dx = offset?.dx, let x = elements[i]["x"] as? Double {
                elements[i]["x"] = x + dx
            }
            if let dy = offset?.dy, let y = elements[i]["y"] as? Double {
                elements[i]["y"] = y + dy
            }
        }

        return try JSONSerialization.data(withJSONObject: elements)
    }

    /// Computes the translation needed so the bounding-box top-left
    /// lands at `target`. Returns nil if neither target coord supplied
    /// (= keep original layout).
    private func computeOffset(
        elements: [[String: Any]],
        target: (x: Double?, y: Double?)
    ) -> (dx: Double, dy: Double)? {
        guard target.x != nil || target.y != nil else { return nil }

        // Bounding-box top-left = min(x), min(y) across all elements.
        // Note: this ignores width/height for max calculation because we
        // only need the top-left for positioning; the bbox's full extent
        // doesn't matter for translation.
        let xs = elements.compactMap { $0["x"] as? Double }
        let ys = elements.compactMap { $0["y"] as? Double }
        guard let minX = xs.min(), let minY = ys.min() else {
            return (target.x ?? 0, target.y ?? 0)
        }
        return (
            dx: (target.x ?? minX) - minX,
            dy: (target.y ?? minY) - minY
        )
    }

    /// Walk a single element's JSON dict and substitute ids using the
    /// supplied mappings. Foreign refs (ids not in our mapping —
    /// pointing to canvas elements outside this item) are left
    /// untouched.
    private func remapIDs(
        in element: [String: Any],
        idMapping: [String: String],
        groupIDMapping: [String: String]
    ) -> [String: Any] {
        var out = element

        // Element's own id.
        if let oldID = out["id"] as? String, let newID = idMapping[oldID] {
            out["id"] = newID
        }

        // text → containerId, generic → frameId — both are scalar id
        // refs to other elements in the same item.
        for key in ["containerId", "frameId"] {
            if let oldRef = out[key] as? String, let newRef = idMapping[oldRef] {
                out[key] = newRef
            }
        }

        // boundElements is on parents (shape with bound text, shape
        // with arrow connections) and lists [{id, type}] entries. We
        // remap each entry's id in place; type is left alone.
        if var bound = out["boundElements"] as? [[String: Any]] {
            for i in bound.indices {
                if let oldID = bound[i]["id"] as? String,
                   let newID = idMapping[oldID] {
                    bound[i]["id"] = newID
                }
            }
            out["boundElements"] = bound
        }

        // arrow/linear bindings — both endpoints have an `elementId`
        // field that points to the bound shape.
        for key in ["startBinding", "endBinding"] {
            if var binding = out[key] as? [String: Any],
               let oldID = binding["elementId"] as? String,
               let newID = idMapping[oldID] {
                binding["elementId"] = newID
                out[key] = binding
            }
        }

        // groupIds — remap each entry through the group-id mapping
        // (separate space from element ids).
        if let groupIDs = out["groupIds"] as? [String] {
            out["groupIds"] = groupIDs.map { groupIDMapping[$0] ?? $0 }
        }

        return out
    }

    // MARK: - Canvas

    @MainActor
    private func applyToCanvas(
        elements: [ExcalidrawElement],
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws {
        guard let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget) else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }
        try await coordinator.addElements(elements)
    }

    // MARK: - Input

    private struct Params {
        var libraryID: String
        var itemID: String
        var x: Double?
        var y: Double?
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
        return Params(
            libraryID: libraryID,
            itemID: itemID,
            x: numeric(json["x"]),
            y: numeric(json["y"])
        )
    }

    /// JSONSerialization may decode numerics as `Int`, `Double`, or
    /// `NSNumber` depending on the literal — coerce to `Double?`.
    private func numeric(_ any: Any?) -> Double? {
        if let n = any as? Double { return n }
        if let n = any as? Int { return Double(n) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}
