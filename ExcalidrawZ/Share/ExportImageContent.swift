import Foundation

enum ExportImageScope: Hashable {
    case all
    case selected
}

/// A scene subset shared by the preview and the exported image, including its media.
struct ExportImageContent {
    let elements: [ExcalidrawElement]
    let files: [String: ExcalidrawFile.ResourceFile]

    init(file: ExcalidrawFile, selectedElementIDs: Set<String>? = nil) {
        let visibleElements = file.elements.filter { !$0.isDeleted }
        if let selectedElementIDs {
            let selectedFrameIDs = Set(visibleElements.compactMap { element -> String? in
                guard case .frameLike = element, selectedElementIDs.contains(element.id) else {
                    return nil
                }
                return element.id
            })
            let includedIDs = Set(visibleElements.compactMap { element -> String? in
                if selectedElementIDs.contains(element.id)
                    || element.frameId.map(selectedFrameIDs.contains) == true {
                    return element.id
                }
                return nil
            })

            // Keep scene order and include container-bound text without adding bound arrows.
            elements = visibleElements.filter { element in
                if includedIDs.contains(element.id) { return true }
                if case .text(let text) = element, let containerID = text.containerId {
                    return includedIDs.contains(containerID)
                }
                return false
            }
        } else {
            elements = visibleElements
        }

        let fileIDs = Set(elements.compactMap { element -> String? in
            switch element {
                case .image(let image): return image.fileId
                case .pdf(let pdf): return pdf.fileId
                default: return nil
            }
        })
        files = file.files.filter { fileIDs.contains($0.key) }
    }
}
