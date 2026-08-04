//
//  OneDriveGraphModelsTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class OneDriveGraphModelsTests: XCTestCase {
    func testMapsDriveItemToProviderNeutralItem() throws {
        let data = Data(
            """
            {
              "id": "item-1",
              "name": "Drawing.excalidraw",
              "size": 2048,
              "createdDateTime": "2026-08-01T01:02:03Z",
              "lastModifiedDateTime": "2026-08-01T02:03:04.123Z",
              "eTag": "revision-1",
              "file": { "mimeType": "application/vnd.excalidraw+json" },
              "parentReference": { "id": "folder-1" }
            }
            """.utf8
        )

        let driveItem = try JSONDecoder.oneDriveGraphDecoder().decode(
            OneDriveDriveItem.self,
            from: data
        )
        let item = driveItem.cloudStorageItem

        XCTAssertEqual(item.id, CloudStorageItemID(rawValue: "item-1"))
        XCTAssertEqual(item.parentID, CloudStorageItemID(rawValue: "folder-1"))
        XCTAssertEqual(item.name, "Drawing.excalidraw")
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.contentType, "application/vnd.excalidraw+json")
        XCTAssertEqual(item.size, 2048)
        XCTAssertEqual(item.revision, "revision-1")
        XCTAssertNil(item.capabilities)
        XCTAssertEqual(item.effectiveCapabilities, .writableFile)
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.modifiedAt)
    }

    func testMapsDeletedDeltaItem() throws {
        let data = Data(
            """
            {
              "value": [
                { "id": "deleted-item", "deleted": {} }
              ],
              "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/drive/root/delta?token=next"
            }
            """.utf8
        )

        let response = try JSONDecoder.oneDriveGraphDecoder().decode(
            OneDriveGraphCollection<OneDriveDriveItem>.self,
            from: data
        )

        XCTAssertEqual(response.value.first?.id, "deleted-item")
        XCTAssertNotNil(response.value.first?.deleted)
        XCTAssertNil(response.nextLink)
        XCTAssertNotNil(response.deltaLink)
    }
}
