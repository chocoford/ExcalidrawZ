//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyDeleteOp(
        _ op: DeleteOp,
        elements: inout [ExcalidrawElement],
        deletedElementIds: inout [String]
    ) throws {
        let index = try indexOfElement(op.id, in: elements)
        elements[index] = markDeleted(elements[index])
        deletedElementIds.append(op.id)
    }

    func markDeleted(_ element: ExcalidrawElement) -> ExcalidrawElement {
        switch element {
            case .text(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .text(item)
            case .generic(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .generic(item)
            case .linear(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .linear(item)
            case .arrow(var item):
                item.isDeleted = true
                bump(&item.version, &item.versionNonce, &item.updated)
                return .arrow(item)
            default:
                return element
        }
    }

}
