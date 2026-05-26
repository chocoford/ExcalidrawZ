//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyMoveOp(
        _ op: MoveOp,
        elements: inout [ExcalidrawElement],
        updatedElementIds: inout [String]
    ) throws {
        let index = try indexOfElement(op.id, in: elements)
        elements[index] = try moveElement(elements[index], dx: op.dx, dy: op.dy)
        updatedElementIds.append(op.id)
    }

    func moveElement(_ element: ExcalidrawElement, dx: Double, dy: Double) throws -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                item.x += dx
                item.y += dy
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                throw AdjustmentError(message: "Move only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }
    }

}
