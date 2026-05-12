//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyAddOp(
        _ op: AddOp,
        elements: inout [ExcalidrawElement],
        canvasActions: inout [CanvasAction]
    ) throws {
        let position = try op.position ?? resolvedPlacePosition(
            op.place,
            skeleton: op.elements,
            existingElements: elements
        )
        canvasActions.append(.insertSkeleton(SkeletonInsertAction(
            skeletons: op.elements,
            regenerateIds: op.regenerateIds,
            position: position,
            focus: op.focus,
            files: op.files,
            captureUpdate: op.captureUpdate,
            sanitize: op.sanitize
        )))
    }

    func resolvedPlacePosition(
        _ place: PlaceHint?,
        skeleton: ExcalidrawCore.JSONValue,
        existingElements: [ExcalidrawElement]
    ) throws -> ExcalidrawCore.MermaidPosition? {
        guard let place else { return nil }
        guard let anchor = existingElements.first(where: { $0.id == place.relativeToId }) else {
            throw AdjustmentError(message: "place.relativeToId \(place.relativeToId) not found.")
        }

        let gap = place.gap ?? 40
        let width = skeleton.numberValue(forKey: "width") ?? 160
        let height = skeleton.numberValue(forKey: "height") ?? 100
        let point: ExcalidrawCore.MermaidPointPosition

        switch place.position {
            case "right":
                point = .init(x: anchor.x + anchor.width + gap, y: anchor.y, anchor: .topLeft)
            case "left":
                point = .init(x: anchor.x - width - gap, y: anchor.y, anchor: .topLeft)
            case "above":
                point = .init(x: anchor.x, y: anchor.y - height - gap, anchor: .topLeft)
            case "inside":
                point = .init(x: anchor.x + gap, y: anchor.y + gap, anchor: .topLeft)
            case "below":
                fallthrough
            default:
                point = .init(x: anchor.x, y: anchor.y + anchor.height + gap, anchor: .topLeft)
        }

        return .point(point)
    }
}

private extension ExcalidrawCore.JSONValue {
    func numberValue(forKey key: String) -> Double? {
        guard case .object(let object) = self,
              case .number(let value)? = object[key] else {
            return nil
        }
        return value
    }
}
