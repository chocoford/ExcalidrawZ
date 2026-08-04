//
//  BoxModelsTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class BoxModelsTests: XCTestCase {
    func testMapsBoxFileToProviderNeutralItem() throws {
        let data = Data(
            """
            {
              "type": "file",
              "id": "12345",
              "name": "Drawing.excalidraw",
              "size": 2048,
              "created_at": "2026-08-01T01:02:03Z",
              "modified_at": "2026-08-01T02:03:04.123Z",
              "etag": "7",
              "parent": { "type": "folder", "id": "99" },
              "permissions": {
                "can_download": true,
                "can_upload": true,
                "can_rename": true,
                "can_delete": false
              }
            }
            """.utf8
        )

        let boxItem = try JSONDecoder.boxDecoder().decode(BoxItem.self, from: data)
        let item = boxItem.cloudStorageItem

        XCTAssertEqual(item.id, CloudStorageItemID(rawValue: "file:12345"))
        XCTAssertEqual(item.parentID, CloudStorageItemID(rawValue: "folder:99"))
        XCTAssertEqual(item.name, "Drawing.excalidraw")
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.size, 2048)
        XCTAssertEqual(item.revision, "7")
        XCTAssertTrue(item.effectiveCapabilities.contains(.download))
        XCTAssertTrue(item.effectiveCapabilities.contains(.updateContent))
        XCTAssertTrue(item.effectiveCapabilities.contains(.rename))
        XCTAssertTrue(item.effectiveCapabilities.contains(.move))
        XCTAssertFalse(item.effectiveCapabilities.contains(.delete))
    }

    func testMapsBoxFolderPermissions() throws {
        let data = Data(
            """
            {
              "type": "folder",
              "id": "0",
              "name": "All Files",
              "permissions": {
                "can_download": true,
                "can_upload": true,
                "can_rename": false,
                "can_delete": false
              }
            }
            """.utf8
        )

        let item = try JSONDecoder.boxDecoder()
            .decode(BoxItem.self, from: data)
            .cloudStorageItem

        XCTAssertEqual(item.id, CloudStorageItemID(rawValue: "folder:0"))
        XCTAssertEqual(item.kind, .folder)
        XCTAssertTrue(item.effectiveCapabilities.contains(.createChildren))
        XCTAssertFalse(item.effectiveCapabilities.contains(.updateContent))
        XCTAssertFalse(item.effectiveCapabilities.contains(.rename))
    }

    func testDecodesNumericEventStreamPosition() throws {
        let data = Data(
            """
            {
              "entries": [{ "event_id": "event-1" }],
              "next_stream_position": 123456
            }
            """.utf8
        )

        let response = try JSONDecoder.boxDecoder().decode(BoxEventCollection.self, from: data)

        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.nextStreamPosition, "123456")
    }

    func testRejectsUntypedBoxItemID() {
        XCTAssertThrowsError(
            try BoxItemIdentity(CloudStorageItemID(rawValue: "12345"))
        )
    }
}
