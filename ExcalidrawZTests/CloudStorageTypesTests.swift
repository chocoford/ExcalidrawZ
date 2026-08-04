//
//  CloudStorageTypesTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class CloudStorageTypesTests: XCTestCase {
    func testLocationCapabilitiesRemainBackwardCompatibleWithPersistedLocations() throws {
        let data = Data(
            """
            {
              "id": "F6F8D336-D2E1-4E27-B622-C0312669193D",
              "providerID": { "rawValue": "onedrive" },
              "accountID": { "rawValue": "account-1" },
              "rootItemID": { "rawValue": "folder-1" },
              "displayName": "OneDrive",
              "createdAt": 0
            }
            """.utf8
        )

        let location = try JSONDecoder().decode(CloudStorageLocation.self, from: data)

        XCTAssertNil(location.rootCapabilities)
        XCTAssertEqual(location.effectiveRootCapabilities, .writableFolder)
    }

    func testItemCapabilitiesRemainBackwardCompatibleWithPersistedItems() throws {
        let data = Data(
            """
            {
              "id": { "rawValue": "file-1" },
              "parentID": { "rawValue": "folder-1" },
              "name": "Drawing.excalidraw",
              "kind": "file"
            }
            """.utf8
        )

        let item = try JSONDecoder().decode(CloudStorageItem.self, from: data)

        XCTAssertNil(item.capabilities)
        XCTAssertTrue(item.effectiveCapabilities.contains(.download))
        XCTAssertTrue(item.effectiveCapabilities.contains(.updateContent))
    }

    func testProviderItemCapabilitiesOverrideBackwardCompatibleDefaults() {
        let item = CloudStorageItem(
            id: CloudStorageItemID(rawValue: "file-1"),
            parentID: CloudStorageItemID(rawValue: "folder-1"),
            name: "Read Only.excalidraw",
            kind: .file,
            contentType: nil,
            size: nil,
            createdAt: nil,
            modifiedAt: nil,
            remoteURL: nil,
            revision: nil,
            capabilities: [.download]
        )

        XCTAssertEqual(item.effectiveCapabilities, [.download])
        XCTAssertFalse(item.effectiveCapabilities.contains(.updateContent))
    }
}
