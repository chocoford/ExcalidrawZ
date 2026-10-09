//
//  ExcalidrawDocumentAppStatePersistenceTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class ExcalidrawDocumentAppStatePersistenceTests: XCTestCase {
    func testDocumentDataStripsRuntimeCollaboratorsAndSetsNativeName() throws {
        let input = Data(#"{"type":"excalidraw","appState":{"collaborators":{},"name":"Untitled"}}"#.utf8)

        let output = try ExcalidrawDocumentAppStatePersistence.documentData(
            input,
            settingNativeFileName: "Lecture Notes"
        )
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let appState = try XCTUnwrap(document["appState"] as? [String: Any])

        XCTAssertNil(appState["collaborators"])
        XCTAssertEqual(appState["name"] as? String, "Lecture Notes")
    }

    func testDocumentDataStripsRuntimeCollaboratorsWithoutNativeName() throws {
        let input = Data(##"{"type":"excalidraw","appState":{"collaborators":{},"viewBackgroundColor":"#ffffff"}}"##.utf8)

        let output = try ExcalidrawDocumentAppStatePersistence.documentData(
            input,
            settingNativeFileName: nil
        )
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let appState = try XCTUnwrap(document["appState"] as? [String: Any])

        XCTAssertNil(appState["collaborators"])
        XCTAssertEqual(appState["viewBackgroundColor"] as? String, "#ffffff")
    }
}
