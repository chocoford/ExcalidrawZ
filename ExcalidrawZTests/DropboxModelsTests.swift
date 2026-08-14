//
//  DropboxModelsTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class DropboxModelsTests: XCTestCase {
    func testUsesDropboxNativeCallbackConvention() {
        let configuration = DropboxConfiguration(appKey: "example-key")

        XCTAssertEqual(configuration.callbackURLScheme, "db-example-key")
        XCTAssertEqual(configuration.redirectURI.absoluteString, "db-example-key://2/token")
    }

    func testReadsAppKeyFromDropboxCallbackScheme() {
        XCTAssertEqual(
            DropboxConfiguration.appKey(
                fromURLSchemes: ["excalidrawz", "db-example-key"]
            ),
            "example-key"
        )
        XCTAssertNil(DropboxConfiguration.appKey(fromURLSchemes: ["excalidrawz"]))
    }

    func testMapsDropboxFileToProviderNeutralItem() throws {
        let data = Data(
            """
            {
              ".tag": "file",
              "name": "Drawing.excalidraw",
              "id": "id:a4ayc_80_OEAAAAAAAAAXw",
              "client_modified": "2026-08-01T01:02:03Z",
              "server_modified": "2026-08-01T02:03:04Z",
              "rev": "a1c10ce0dd78",
              "size": 2048,
              "path_lower": "/drawings/drawing.excalidraw",
              "path_display": "/Drawings/Drawing.excalidraw"
            }
            """.utf8
        )

        let metadata = try JSONDecoder.dropboxDecoder().decode(DropboxMetadata.self, from: data)
        let parentID = CloudStorageItemID(rawValue: "id:parent")
        let item = try XCTUnwrap(metadata.cloudStorageItem(parentID: parentID))

        XCTAssertEqual(item.id, CloudStorageItemID(rawValue: "id:a4ayc_80_OEAAAAAAAAAXw"))
        XCTAssertEqual(item.parentID, parentID)
        XCTAssertEqual(item.name, "Drawing.excalidraw")
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.size, 2048)
        XCTAssertEqual(item.revision, "a1c10ce0dd78")
        XCTAssertEqual(item.effectiveCapabilities, .writableFile)
    }

    func testDecodesFileMetadataWithoutSubtypeTag() throws {
        let data = Data(
            """
            {
              "name": "Drawing.excalidraw",
              "id": "id:file",
              "client_modified": "2026-08-01T01:02:03Z",
              "server_modified": "2026-08-01T02:03:04Z",
              "rev": "a1c10ce0dd78",
              "size": 2048,
              "path_lower": "/drawings/drawing.excalidraw",
              "path_display": "/Drawings/Drawing.excalidraw"
            }
            """.utf8
        )

        let metadata = try JSONDecoder.dropboxDecoder().decode(DropboxMetadata.self, from: data)

        guard case .file(let file) = metadata else {
            return XCTFail("Expected tagless Dropbox file metadata to decode as a file.")
        }
        XCTAssertEqual(file.id, "id:file")
        XCTAssertEqual(file.rev, "a1c10ce0dd78")
    }

    func testDecodesFolderMetadataWithoutSubtypeTag() throws {
        let data = Data(
            """
            {
              "name": "Drawings",
              "id": "id:folder",
              "path_lower": "/drawings",
              "path_display": "/Drawings"
            }
            """.utf8
        )

        let metadata = try JSONDecoder.dropboxDecoder().decode(DropboxMetadata.self, from: data)

        guard case .folder(let folder) = metadata else {
            return XCTFail("Expected tagless Dropbox folder metadata to decode as a folder.")
        }
        XCTAssertEqual(folder.id, "id:folder")
    }

    func testDecodesDropboxFolderAndDeletedMetadata() throws {
        let data = Data(
            """
            {
              "entries": [
                {
                  ".tag": "folder",
                  "name": "Drawings",
                  "id": "id:folder",
                  "path_lower": "/drawings",
                  "path_display": "/Drawings"
                },
                {
                  ".tag": "deleted",
                  "name": "Old.excalidraw",
                  "path_lower": "/drawings/old.excalidraw",
                  "path_display": "/Drawings/Old.excalidraw"
                }
              ],
              "cursor": "cursor-1",
              "has_more": false
            }
            """.utf8
        )

        let result = try JSONDecoder.dropboxDecoder().decode(
            DropboxListFolderResult.self,
            from: data
        )

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].itemID, CloudStorageItemID(rawValue: "id:folder"))
        XCTAssertNil(result.entries[1].itemID)
        XCTAssertEqual(result.entries[1].pathLower, "/drawings/old.excalidraw")
        XCTAssertEqual(result.cursor, "cursor-1")
        XCTAssertFalse(result.hasMore)
    }

    func testPathIndexRemapsDescendantsWhenFolderIsRenamed() {
        let rootID = CloudStorageItemID(rawValue: "root")
        let folderID = CloudStorageItemID(rawValue: "id:folder")
        let fileID = CloudStorageItemID(rawValue: "id:file")
        var index = DropboxItemPathIndex()
        index.reset(rootID: rootID, rootPath: "/drawings")
        index.track(itemID: folderID, path: "/drawings/section", isFolder: true)
        index.track(
            itemID: fileID,
            path: "/drawings/section/file.excalidraw",
            isFolder: false
        )

        index.track(itemID: folderID, path: "/drawings/renamed", isFolder: true)

        XCTAssertEqual(
            index.parentID(for: "/drawings/renamed/file.excalidraw"),
            folderID
        )
        XCTAssertEqual(
            index.itemID(for: "/drawings/renamed/file.excalidraw"),
            fileID
        )
        XCTAssertNil(index.itemID(for: "/drawings/section/file.excalidraw"))
    }

    func testPathIndexRemovesFolderDescendants() {
        let rootID = CloudStorageItemID(rawValue: "root")
        let folderID = CloudStorageItemID(rawValue: "id:folder")
        let fileID = CloudStorageItemID(rawValue: "id:file")
        var index = DropboxItemPathIndex()
        index.reset(rootID: rootID, rootPath: "")
        index.track(itemID: folderID, path: "/section", isFolder: true)
        index.track(itemID: fileID, path: "/section/file.excalidraw", isFolder: false)

        index.remove(folderID)

        XCTAssertNil(index.itemID(for: "/section"))
        XCTAssertNil(index.itemID(for: "/section/file.excalidraw"))
    }
}
