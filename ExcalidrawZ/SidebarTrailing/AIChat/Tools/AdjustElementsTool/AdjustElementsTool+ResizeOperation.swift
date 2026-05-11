//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyResizeOp(
        _ op: ResizeOp,
        elements: inout [ExcalidrawElement],
        updatedElementIds: inout [String]
    ) throws {
        let index = try indexOfElement(op.id, in: elements)
        elements[index] = try resizeElement(elements[index], op: op)
        updatedElementIds.append(op.id)
    }

    func resizeElement(_ element: ExcalidrawElement, op: ResizeOp) throws -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.width = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                item.height = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.width = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                item.height = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                let newW = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                let newH = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                item.points = scaledPoints(item.points, oldW: item.width, oldH: item.height, newW: newW, newH: newH)
                item.width = newW
                item.height = newH
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                let newW = resolvedDimension(current: item.width, absolute: op.width, delta: op.dw)
                let newH = resolvedDimension(current: item.height, absolute: op.height, delta: op.dh)
                item.points = scaledPoints(item.points, oldW: item.width, oldH: item.height, newW: newW, newH: newH)
                item.width = newW
                item.height = newH
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                throw AdjustmentError(message: "Resize only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }
    }

    /// Scale linear points so the bounding box matches `newW × newH`. If a
    /// dimension was 0 (e.g. straight horizontal line has height = 0), leave
    /// that axis alone — there's nothing to scale.
    func scaledPoints(_ points: [Point], oldW: Double, oldH: Double, newW: Double, newH: Double) -> [Point] {
        let sx = oldW > 0 ? newW / oldW : 1
        let sy = oldH > 0 ? newH / oldH : 1
        return points.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
    }

}
