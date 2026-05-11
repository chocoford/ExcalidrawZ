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
}
