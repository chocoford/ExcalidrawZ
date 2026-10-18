import XCTest
@testable import ExcalidrawZ

final class ExportImageContentTests: XCTestCase {
    func testSelectionIncludesBoundTextButNotOtherBoundElements() throws {
        let text = try element("label", type: "text", extra: ["containerId": "shape"])
        let shape = try element("shape", extra: ["boundElements": [
            ["id": "label", "type": "text"], ["id": "arrow", "type": "arrow"]
        ]])
        let arrow = try element("arrow", type: "arrow", extra: ["points": [[0, 0], [10, 10]]])
        let file = file(elements: [text, shape, arrow, try element("unrelated")])

        let content = ExportImageContent(file: file, selectedElementIDs: ["shape"])

        XCTAssertEqual(content.elements.map(\.id), ["label", "shape"])
    }

    func testSelectedFrameIncludesChildrenAndTheirBoundTextInSceneOrder() throws {
        let file = file(elements: [
            try element("child", extra: ["frameId": "frame"]),
            try element("label", type: "text", extra: ["containerId": "child"]),
            try element("otherChild", extra: ["frameId": "otherFrame"]),
            try element("frame", type: "frame"),
            try element("deletedChild", extra: ["frameId": "frame", "isDeleted": true])
        ])

        let content = ExportImageContent(file: file, selectedElementIDs: ["frame", "child"])

        XCTAssertEqual(content.elements.map(\.id), ["child", "label", "frame"])
    }

    func testDeletedOrMissingSelectionDoesNotExportTheWholeScene() throws {
        let file = file(elements: [
            try element("visible"), try element("deleted", extra: ["isDeleted": true])
        ])

        for ids: Set<String> in [[], ["missing"], ["deleted"]] {
            let content = ExportImageContent(file: file, selectedElementIDs: ids)
            XCTAssertTrue(content.elements.isEmpty)
            XCTAssertTrue(content.files.isEmpty)
        }
    }

    func testSelectionKeepsOnlyReferencedMediaIncludingSharedResources() throws {
        let file = file(elements: [
            try element("image1", type: "image", extra: ["fileId": "shared"]),
            try element("image2", type: "image", extra: ["fileId": "shared"]),
            try element("pdf", type: "pdf", extra: ["fileId": "pdfData"]),
            try element("otherImage", type: "image", extra: ["fileId": "other"])
        ], resourceIDs: ["shared", "pdfData", "other", "unused"])

        let content = ExportImageContent(file: file, selectedElementIDs: ["image1", "image2", "pdf"])

        XCTAssertEqual(content.elements.map(\.id), ["image1", "image2", "pdf"])
        XCTAssertEqual(Set(content.files.keys), ["shared", "pdfData"])
    }

    func testAllScopeRetainsVisibleElementsAndTheirMedia() throws {
        let file = file(elements: [
            try element("shape"),
            try element("image", type: "image", extra: ["fileId": "used"]),
            try element("deletedImage", type: "image", extra: ["fileId": "deleted", "isDeleted": true])
        ], resourceIDs: ["used", "deleted", "unused"])

        let content = ExportImageContent(file: file)

        XCTAssertEqual(content.elements.map(\.id), ["shape", "image"])
        XCTAssertEqual(Set(content.files.keys), ["used"])
    }

    private func file(elements: [ExcalidrawElement], resourceIDs: [String] = []) -> ExcalidrawFile {
        ExcalidrawFile(
            source: "https://excalidraw.com",
            files: Dictionary(uniqueKeysWithValues: resourceIDs.map { id in
                (id, ExcalidrawFile.ResourceFile(mimeType: "image/png", id: id, dataURL: "data:image/png;base64,"))
            }),
            version: 2,
            elements: elements,
            appState: .init(),
            type: "excalidraw"
        )
    }

    private func element(
        _ id: String,
        type: String = "rectangle",
        extra: [String: Any] = [:]
    ) throws -> ExcalidrawElement {
        var json: [String: Any] = [
            "id": id, "type": type, "x": 0, "y": 0, "width": 100, "height": 80,
            "strokeColor": "#000000", "backgroundColor": "transparent",
            "fillStyle": "solid", "strokeWidth": 1, "strokeStyle": "solid",
            "roughness": 1, "opacity": 100, "angle": 0, "seed": 1,
            "version": 1, "versionNonce": 1, "isDeleted": false, "groupIds": [],
            "fontSize": 20, "fontFamily": 1, "text": "Label", "originalText": "Label",
            "textAlign": "center", "verticalAlign": "middle", "autoResize": true,
            "status": "saved", "scale": [1, 1], "currentPage": 1, "totalPages": 1
        ]
        json.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ExcalidrawElement.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
