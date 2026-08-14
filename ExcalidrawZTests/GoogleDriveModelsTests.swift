//
//  GoogleDriveModelsTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class GoogleDriveModelsTests: XCTestCase {
    func testUsesFullDriveScopeForFolderConnections() {
        XCTAssertEqual(
            GoogleDriveConfiguration.driveScope,
            "https://www.googleapis.com/auth/drive"
        )
    }

    func testLegacyCredentialRequiresScopeUpgrade() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "accountID": "account-1",
            "displayName": "Example",
            "accessToken": "access-token",
            "refreshToken": "refresh-token",
            "expiresAt": 0,
        ])

        let credential = try JSONDecoder().decode(GoogleDriveCredential.self, from: data)

        XCTAssertFalse(credential.hasRequiredScope)
    }

    func testUsesReverseClientIDCallbackConvention() {
        let configuration = GoogleDriveConfiguration(
            clientID: "123456789-example.apps.googleusercontent.com"
        )

        XCTAssertEqual(
            configuration.callbackURLScheme,
            "com.googleusercontent.apps.123456789-example"
        )
        XCTAssertEqual(
            configuration.redirectURI.absoluteString,
            "com.googleusercontent.apps.123456789-example:/oauth2redirect"
        )
    }

    func testMapsGoogleDriveFileToProviderNeutralItem() throws {
        let data = Data(
            """
            {
              "id": "file-1",
              "name": "Drawing.excalidraw",
              "mimeType": "application/octet-stream",
              "size": "2048",
              "createdTime": "2026-08-01T01:02:03.000Z",
              "modifiedTime": "2026-08-01T02:03:04.000Z",
              "webViewLink": "https://drive.google.com/file/d/file-1/view",
              "version": "42",
              "parents": ["folder-1"],
              "capabilities": {
                "canDownload": true,
                "canAddChildren": false,
                "canEdit": true,
                "canRename": true,
                "canMoveItemWithinDrive": true,
                "canDelete": true
              },
              "trashed": false
            }
            """.utf8
        )

        let file = try JSONDecoder.googleDriveDecoder().decode(GoogleDriveFile.self, from: data)
        let item = file.cloudStorageItem

        XCTAssertEqual(item.id, CloudStorageItemID(rawValue: "file-1"))
        XCTAssertEqual(item.parentID, CloudStorageItemID(rawValue: "folder-1"))
        XCTAssertEqual(item.name, "Drawing.excalidraw")
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.size, 2048)
        XCTAssertEqual(item.revision, "42")
        XCTAssertEqual(item.effectiveCapabilities, .writableFile)
    }

    func testMapsGoogleDriveFolderWithoutDownloadCapability() throws {
        let data = Data(
            """
            {
              "id": "folder-1",
              "name": "Drawings",
              "mimeType": "application/vnd.google-apps.folder",
              "capabilities": {
                "canDownload": true,
                "canAddChildren": true,
                "canEdit": true,
                "canRename": true,
                "canMoveItemWithinDrive": true,
                "canDelete": true
              },
              "trashed": false
            }
            """.utf8
        )

        let folder = try JSONDecoder.googleDriveDecoder().decode(GoogleDriveFile.self, from: data)
        let item = folder.cloudStorageItem

        XCTAssertEqual(item.kind, .folder)
        XCTAssertFalse(item.effectiveCapabilities.contains(.download))
        XCTAssertTrue(item.effectiveCapabilities.contains(.createChildren))
    }

    func testContentChecksumTakesPriorityOverMetadataVersion() throws {
        let data = Data(
            """
            {
              "id": "file-1",
              "name": "Drawing.excalidraw",
              "mimeType": "application/octet-stream",
              "version": "43",
              "sha256Checksum": "content-checksum",
              "trashed": false
            }
            """.utf8
        )

        let file = try JSONDecoder.googleDriveDecoder().decode(GoogleDriveFile.self, from: data)

        XCTAssertEqual(file.cloudStorageItem.revision, "content-checksum")
    }
}
