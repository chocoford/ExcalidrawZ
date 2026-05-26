//
//  AdjustElementsTool operation module.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyUpdateOp(
        _ op: UpdateOp,
        elements: inout [ExcalidrawElement],
        updatedElementIds: inout [String]
    ) throws {
        let result = try patchElement(
            elements,
            targetIndex: try indexOfElement(op.id, in: elements),
            patch: op.patch
        )
        elements = result.elements
        updatedElementIds.append(op.id)
        for parentID in result.touchedParentIDs where !updatedElementIds.contains(parentID) {
            updatedElementIds.append(parentID)
        }
    }

    func patchElement(
        _ elements: [ExcalidrawElement],
        targetIndex: Int,
        patch: ElementPatch
    ) throws -> PatchResult {
        let stylePatch = hydratedStylePreset(patch.stylePreset).merged(with: patch.style)
        var newElements = elements
        var touchedParents: [String] = []
        let element = elements[targetIndex]

        switch element {
            case .text(var item):
                if let text = patch.text ?? patch.label {
                    item.text = text
                    item.originalText = text
                    if patch.bounds?.width == nil {
                        item.width = defaultTextWidth(text: text, fontSize: stylePatch.fontSize ?? item.fontSize)
                    }
                    if patch.bounds?.height == nil {
                        item.height = defaultTextHeight(text: text, fontSize: stylePatch.fontSize ?? item.fontSize)
                    }
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let fontSize = stylePatch.fontSize {
                    item.fontSize = fontSize
                }
                if let fontFamily = stylePatch.fontFamily {
                    item.fontFamily = .int(Int(fontFamily))
                }
                if let textAlign = parseTextAlign(stylePatch.textAlign) {
                    item.textAlign = textAlign
                }
                if let verticalAlign = parseVerticalAlign(stylePatch.verticalAlign) {
                    item.verticalAlign = verticalAlign
                }
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }

                // containerId mutation: bind / unbind text → container shape.
                if let containerPatch = patch.containerId {
                    let oldContainerID = item.containerId
                    let newContainerID = containerPatch.value
                    if oldContainerID != newContainerID {
                        // Detach from old container.
                        if let oldID = oldContainerID,
                           let oldIdx = newElements.firstIndex(where: { $0.id == oldID }) {
                            newElements[oldIdx] = removeBoundElement(newElements[oldIdx], id: item.id)
                            touchedParents.append(oldID)
                        }
                        // Attach to new container (if any) and recenter inside it.
                        if let newID = newContainerID {
                            guard let newIdx = newElements.firstIndex(where: { $0.id == newID }) else {
                                throw AdjustmentError(message: "Container \(newID) not found.")
                            }
                            guard case .generic = newElements[newIdx] else {
                                throw AdjustmentError(message: "Container \(newID) must be rectangle/ellipse/diamond.")
                            }
                            let container = newElements[newIdx]
                            item.x = container.x + (container.width - item.width) / 2
                            item.y = container.y + (container.height - item.height) / 2
                            newElements[newIdx] = appendBoundElement(
                                newElements[newIdx],
                                entry: ExcalidrawBoundElement(id: item.id, type: .text)
                            )
                            touchedParents.append(newID)
                        }
                        item.containerId = newContainerID
                    }
                }

                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .text(item)

            case .generic(var item):
                if patch.text != nil || patch.label != nil {
                    throw AdjustmentError(message: "Text patch is only supported for text elements.")
                }
                if patch.containerId != nil {
                    throw AdjustmentError(message: "containerId only applies to text elements.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .generic(item)

            case .linear(var item):
                if patch.text != nil || patch.label != nil || patch.containerId != nil {
                    throw AdjustmentError(message: "Lines accept only bounds/style patches.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .linear(item)

            case .arrow(var item):
                if patch.text != nil || patch.label != nil || patch.containerId != nil {
                    throw AdjustmentError(message: "Arrows accept only bounds/style patches.")
                }
                applyBoundsPatch(&item.x, &item.y, &item.width, &item.height, patch.bounds)
                applyCommonStylePatch(
                    strokeColor: &item.strokeColor,
                    backgroundColor: &item.backgroundColor,
                    strokeWidth: &item.strokeWidth,
                    roughness: &item.roughness,
                    opacity: &item.opacity,
                    style: stylePatch
                )
                if let locked = patch.locked {
                    item.locked = locked
                }
                if let link = patch.link {
                    item.link = link
                }
                bump(&item.version, &item.versionNonce, &item.updated)
                newElements[targetIndex] = .arrow(item)

            default:
                throw AdjustmentError(message: "Patch only supports text, rectangle, ellipse, diamond, line, and arrow.")
        }

        return PatchResult(elements: newElements, touchedParentIDs: touchedParents)
    }

}
