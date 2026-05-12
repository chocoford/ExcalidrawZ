//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyMermaidOp(
        _ op: MermaidOp,
        canvasActions: inout [CanvasAction]
    ) throws {
        let definition = op.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else {
            throw AdjustmentError(message: "mermaid requires a non-empty definition.")
        }
        canvasActions.append(.insertMermaid(op))
    }

    func applyConnectOp(
        _ op: ConnectOp,
        elements: [ExcalidrawElement],
        canvasActions: inout [CanvasAction]
    ) throws {
        let from = op.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = op.to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            throw AdjustmentError(message: "connect requires non-empty `from` and `to` element ids.")
        }
        guard elements.contains(where: { $0.id == from && !$0.isDeleted }) else {
            throw AdjustmentError(message: "connect.from element \(from) not found or deleted.")
        }
        guard elements.contains(where: { $0.id == to && !$0.isDeleted }) else {
            throw AdjustmentError(message: "connect.to element \(to) not found or deleted.")
        }
        if let arrow = op.arrow, case .object = arrow {
            // Valid custom arrow options.
        } else if op.arrow != nil {
            throw AdjustmentError(message: "connect.arrow must be an object when provided.")
        }
        canvasActions.append(.connect(ConnectOp(
            op: op.op,
            from: from,
            to: to,
            arrow: op.arrow,
            captureUpdate: op.captureUpdate
        )))
    }
}
