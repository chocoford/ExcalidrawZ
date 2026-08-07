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

    func testMetadataOperationRoundTripsThroughPersistence() throws {
        let operation = CloudStorageMetadataOperation(
            id: UUID(uuidString: "7BE785DB-94AF-40BB-93F7-59E5B0A759C4")!,
            kind: .createFile,
            itemID: CloudStorageItemID(rawValue: "local-pending:file"),
            parentID: CloudStorageItemID(rawValue: "folder-1"),
            name: "Drawing.excalidraw",
            createdAt: Date(timeIntervalSince1970: 123)
        )

        let decoded = try JSONDecoder().decode(
            CloudStorageMetadataOperation.self,
            from: JSONEncoder().encode(operation)
        )

        XCTAssertEqual(decoded, operation)
    }

    func testMetadataOperationReplacesProvisionalItemAndParentIdentities() {
        let operation = CloudStorageMetadataOperation(
            kind: .moveItem,
            itemID: CloudStorageItemID(rawValue: "local-pending:file"),
            parentID: CloudStorageItemID(rawValue: "local-pending:folder"),
            name: "Renamed.excalidraw"
        )
        let replaced = operation.replacingItemIDs(using: [
            CloudStorageItemID(rawValue: "local-pending:file"):
                CloudStorageItemID(rawValue: "remote-file"),
            CloudStorageItemID(rawValue: "local-pending:folder"):
                CloudStorageItemID(rawValue: "remote-folder"),
        ])

        XCTAssertEqual(replaced.itemID.rawValue, "remote-file")
        XCTAssertEqual(replaced.parentID?.rawValue, "remote-folder")
        XCTAssertEqual(replaced.name, "Renamed.excalidraw")
    }

    func testCloudDocumentCanMigrateStorageIdentityWithoutChangingActiveFileIdentity() {
        let locationID = UUID(uuidString: "F6F8D336-D2E1-4E27-B622-C0312669193D")!
        let provisional = CloudStorageDocumentReference(
            locationID: locationID,
            providerID: CloudStorageProviderID(rawValue: "dropbox"),
            accountID: CloudStorageAccountID(rawValue: "account-1"),
            itemID: CloudStorageItemID(rawValue: "local-pending:file"),
            lastKnownName: "Drawing.excalidraw"
        )
        let remote = CloudStorageDocumentReference(
            locationID: locationID,
            providerID: provisional.providerID,
            accountID: provisional.accountID,
            itemID: CloudStorageItemID(rawValue: "remote-file"),
            lastKnownName: provisional.lastKnownName,
            activeFileID: provisional.activeFileID
        )

        XCTAssertNotEqual(remote.id, provisional.id)
        XCTAssertEqual(remote.activeFileID, provisional.activeFileID)
        XCTAssertEqual(
            FileState.ActiveFile.cloudStorageFile(remote).id,
            FileState.ActiveFile.cloudStorageFile(provisional).id
        )
        XCTAssertEqual(
            FileState.ActiveFile.cloudStorageFile(remote).canonicalID,
            remote.id
        )
    }

    func testCloudDocumentActiveFileIdentityIsNotPersisted() throws {
        let reference = CloudStorageDocumentReference(
            locationID: UUID(uuidString: "F6F8D336-D2E1-4E27-B622-C0312669193D")!,
            providerID: CloudStorageProviderID(rawValue: "dropbox"),
            accountID: CloudStorageAccountID(rawValue: "account-1"),
            itemID: CloudStorageItemID(rawValue: "remote-file"),
            lastKnownName: "Drawing.excalidraw",
            activeFileID: "previous-session-id"
        )

        let decoded = try JSONDecoder().decode(
            CloudStorageDocumentReference.self,
            from: JSONEncoder().encode(reference)
        )

        XCTAssertEqual(decoded.activeFileID, decoded.id)
        XCTAssertNotEqual(decoded.activeFileID, reference.activeFileID)
    }

    func testCloudCheckpointIdentityIgnoresPresentationMetadata() {
        let locationID = UUID(uuidString: "F6F8D336-D2E1-4E27-B622-C0312669193D")!
        let original = CloudStorageDocumentReference(
            locationID: locationID,
            providerID: .dropbox,
            accountID: CloudStorageAccountID(rawValue: "account-1"),
            itemID: CloudStorageItemID(rawValue: "remote-file"),
            lastKnownName: "Original.excalidraw",
            lastKnownModifiedAt: Date(timeIntervalSince1970: 100)
        )
        let renamed = CloudStorageDocumentReference(
            locationID: locationID,
            providerID: .dropbox,
            accountID: CloudStorageAccountID(rawValue: "account-1"),
            itemID: original.itemID,
            lastKnownName: "Renamed.excalidraw",
            lastKnownModifiedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(original.checkpointURL, renamed.checkpointURL)
    }

    func testCloudCheckpointIdentityChangesWithProviderItemIdentity() {
        let locationID = UUID(uuidString: "F6F8D336-D2E1-4E27-B622-C0312669193D")!
        let provisionalURL = CloudStorageDocumentReference.checkpointURL(
            locationID: locationID,
            itemID: CloudStorageItemID(rawValue: "local-pending:file")
        )
        let remoteURL = CloudStorageDocumentReference.checkpointURL(
            locationID: locationID,
            itemID: CloudStorageItemID(rawValue: "remote-file")
        )

        XCTAssertNotEqual(provisionalURL, remoteURL)
    }
}
