//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyAddLabeledShapeOp(
        _ op: AddLabeledShapeOp,
        elements: inout [ExcalidrawElement],
        createdElementIds: inout [String]
    ) throws {
        let result = try hydrateAddLabeledShapeOp(op, existingElements: elements)
        elements.append(contentsOf: result.elements)
        createdElementIds.append(contentsOf: result.elements.map(\.id))
    }

    func hydrateAddLabeledShapeOp(
        _ op: AddLabeledShapeOp,
        existingElements: [ExcalidrawElement]
    ) throws -> AddLabeledShapeOpResult {
        let text = op.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AdjustmentError(message: "addLabeledShape requires non-empty text.")
        }

        let shapeType = try parseWrapType(op.shape)
        let style = hydratedStylePreset(op.stylePreset).merged(with: op.style)
        let fontSize = style.fontSize ?? 20
        let textWidth = defaultTextWidth(text: text, fontSize: fontSize)
        let textHeight = defaultTextHeight(text: text, fontSize: fontSize)
        let width = max(1, op.width ?? max(120, textWidth + 48))
        let height = max(1, op.height ?? max(72, textHeight + 32))
        let fallbackOrigin = resolveInsertionOrigin(
            height: height,
            existingElements: existingElements
        )
        let origin = (
            x: op.x ?? fallbackOrigin.x,
            y: op.y ?? fallbackOrigin.y
        )
        let shapeID = ExcalidrawNanoID.make()
        let textID = ExcalidrawNanoID.make()
        let now = nowMillis()

        let shape = ExcalidrawGenericElement(
            type: shapeType,
            id: shapeID,
            x: origin.x,
            y: origin.y,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: style.backgroundColor ?? "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 2,
            strokeStyle: .solid,
            roundness: shapeType == .rectangle ? ExcalidrawRoundness(type: .adaptiveRadius, value: nil) : nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: width,
            height: height,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [ExcalidrawBoundElement(id: textID, type: .text)],
            updated: now,
            link: nil,
            locked: false,
            customData: nil,
            strokeSharpness: nil
        )

        let label = ExcalidrawTextElement(
            type: .text,
            id: textID,
            x: origin.x + (width - textWidth) / 2,
            y: origin.y + (height - textHeight) / 2,
            strokeColor: style.strokeColor ?? "#1e1e1e",
            backgroundColor: "transparent",
            fillStyle: .solid,
            strokeWidth: style.strokeWidth ?? 1,
            strokeStyle: .solid,
            roundness: nil,
            roughness: style.roughness ?? 1,
            opacity: style.opacity ?? 100,
            width: textWidth,
            height: textHeight,
            angle: 0,
            seed: randomSeed(),
            version: 1,
            versionNonce: randomNonce(),
            index: nil,
            isDeleted: false,
            groupIds: [],
            frameId: nil,
            boundElements: [],
            updated: now,
            link: nil,
            locked: false,
            customData: nil,
            fontSize: fontSize,
            fontFamily: .int(Int(style.fontFamily ?? 5)),
            text: text,
            textAlign: .center,
            verticalAlign: .middle,
            containerId: shapeID,
            originalText: text,
            autoResize: true,
            lineHeight: 1.25
        )

        return AddLabeledShapeOpResult(elements: [.generic(shape), .text(label)])
    }


}
