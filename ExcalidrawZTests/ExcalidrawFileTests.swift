//
//  ExcalidrawFileTests.swift
//  ExcalidrawZTests
//
//  Created by Claude on 2025/11/17.
//

import XCTest
@testable import ExcalidrawZ

/// Tests for ExcalidrawFile model encoding/decoding functionality
/// This test class demonstrates how to test data model serialization and deserialization
final class ExcalidrawFileTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        // Called before each test method
        // Initialize test objects here if needed
    }

    override func tearDownWithError() throws {
        // Called after each test method
        // Clean up test data here if needed
    }

    // MARK: - Basic Encoding/Decoding Tests

    /// Test: Create a minimal ExcalidrawFile and verify its properties
    func testExcalidrawFileCreation() throws {
        // Arrange - Prepare test data
        let expectedSource = "https://excalidraw.com"
        let expectedVersion = 2
        let expectedType = "excalidraw"

        // Act - Execute the operation to test
        let file = ExcalidrawFile(
            source: expectedSource,
            files: [:],
            version: expectedVersion,
            elements: [],
            appState: ExcalidrawFile.AppState(),
            type: expectedType
        )

        // Assert - Verify results match expectations
        XCTAssertEqual(file.source, expectedSource, "Source should match")
        XCTAssertEqual(file.version, expectedVersion, "Version should match")
        XCTAssertEqual(file.type, expectedType, "Type should match")
        XCTAssertTrue(file.elements.isEmpty, "Elements should be empty")
        XCTAssertTrue(file.files.isEmpty, "Files should be empty")
        XCTAssertNotNil(file.id, "ID should be automatically generated")
    }

    /// Test: JSON encoding functionality of ExcalidrawFile
    func testExcalidrawFileEncoding() throws {
        // Arrange
        let file = ExcalidrawFile(
            source: "https://excalidraw.com",
            files: [:],
            version: 2,
            elements: [],
            appState: ExcalidrawFile.AppState(
                gridSize: 20,
                viewBackgroundColor: "#ffffff"
            ),
            type: "excalidraw"
        )

        // Act - Encode object to JSON data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(file)

        // Assert
        XCTAssertNotNil(jsonData, "Encoded data should not be nil")
        XCTAssertGreaterThan(jsonData.count, 0, "Encoded data should have content")

        // Verify JSON structure (optional)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(jsonObject, "Should be parseable as JSON object")
        XCTAssertEqual(jsonObject?["source"] as? String, "https://excalidraw.com")
        XCTAssertEqual(jsonObject?["version"] as? Int, 2)
        XCTAssertEqual(jsonObject?["type"] as? String, "excalidraw")
    }

    /// Test: JSON decoding functionality of ExcalidrawFile
    func testExcalidrawFileDecoding() throws {
        // Arrange - Get test resources directory
        let testBundle = Bundle(for: type(of: self))
        guard let resourcesURL = testBundle.resourceURL?.appendingPathComponent("TestResources") else {
            XCTFail("TestResources directory not found")
            return
        }

        // Get all .excalidraw files
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter({ $0.pathExtension == "excalidraw" }) else {
            XCTFail("Failed to read TestResources directory")
            return
        }

        XCTAssertFalse(files.isEmpty, "TestResources should contain at least one .excalidraw file")

        // Act & Assert - Test each file
        let decoder = JSONDecoder()
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            print("Testing: \(fileName)")

            let data = try Data(contentsOf: fileURL)
            XCTAssertGreaterThan(data.count, 0, "\(fileName) should not be empty")

            let file = try decoder.decode(ExcalidrawFile.self, from: data)

            // Verify basic structure
            XCTAssertEqual(file.type, "excalidraw", "\(fileName): type mismatch")
            XCTAssertEqual(file.version, 2, "\(fileName): version mismatch")
            XCTAssertNotNil(file.source, "\(fileName): source is nil")

            // Test round-trip
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(file)
            let decodedFile = try decoder.decode(ExcalidrawFile.self, from: encodedData)

            XCTAssertEqual(decodedFile.type, file.type, "\(fileName): round-trip type mismatch")
            XCTAssertEqual(decodedFile.elements.count, file.elements.count, "\(fileName): round-trip elements mismatch")
        }

        print("✓ Tested \(files.count) files")
    }

    /// Test: Encode then decode, verify round-trip consistency
    func testExcalidrawFileEncodingDecodingRoundTrip() throws {
        // Arrange - Create original object
        let originalFile = ExcalidrawFile(
            source: "https://excalidraw.com",
            files: [:],
            version: 2,
            elements: [],
            appState: ExcalidrawFile.AppState(
                gridSize: 30,
                viewBackgroundColor: "#f0f0f0"
            ),
            type: "excalidraw"
        )

        // Act - Encode then decode
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(originalFile)

        let decoder = JSONDecoder()
        let decodedFile = try decoder.decode(ExcalidrawFile.self, from: jsonData)

        // Assert - Verify key properties match (note: id is regenerated, so we don't compare it)
        XCTAssertEqual(decodedFile.source, originalFile.source)
        XCTAssertEqual(decodedFile.version, originalFile.version)
        XCTAssertEqual(decodedFile.type, originalFile.type)
        XCTAssertEqual(decodedFile.appState.gridSize, originalFile.appState.gridSize)
        XCTAssertEqual(decodedFile.appState.viewBackgroundColor, originalFile.appState.viewBackgroundColor)
    }

    // MARK: - ResourceFile Tests

    /// Test: ResourceFile timestamp decoding (from milliseconds)
    func testResourceFileTimestampDecoding() throws {
        // Arrange - Create JSON with timestamps
        // Excalidraw uses millisecond timestamps
        let timestamp: Int64 = 1700000000000 // 2023-11-14 22:13:20 UTC
        let jsonString = """
        {
            "mimeType": "image/png",
            "id": "test-image-id",
            "created": \(timestamp),
            "dataURL": "data:image/png;base64,iVBORw0KG...",
            "lastRetrieved": \(timestamp)
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let resourceFile = try decoder.decode(ExcalidrawFile.ResourceFile.self, from: jsonData)

        // Assert
        XCTAssertEqual(resourceFile.mimeType, "image/png")
        XCTAssertEqual(resourceFile.id, "test-image-id")
        XCTAssertNotNil(resourceFile.createdAt)
        XCTAssertNotNil(resourceFile.lastRetrievedAt)

        // Verify timestamp conversion is correct (milliseconds -> seconds)
        let expectedDate = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        if let createdAt = resourceFile.createdAt {
            XCTAssertEqual(createdAt.timeIntervalSince1970,
                           expectedDate.timeIntervalSince1970,
                           accuracy: 1.0,
                           "Timestamp should be correctly converted")
        } else {
            XCTFail("createdAt should not be nil")
        }
    }

    /// Test: ResourceFile timestamp encoding (convert to milliseconds)
    func testResourceFileTimestampEncoding() throws {
        // Arrange - Create ResourceFile via JSON decoding since it has custom init(from:)
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC
        let timestampMs = Int64(date.timeIntervalSince1970 * 1000)

        let jsonString = """
        {
            "mimeType": "image/jpeg",
            "id": "test-id",
            "created": \(timestampMs),
            "dataURL": "data:image/jpeg;base64,test",
            "lastRetrieved": \(timestampMs)
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        let resourceFile = try decoder.decode(ExcalidrawFile.ResourceFile.self, from: jsonData)

        // Act - Re-encode it
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(resourceFile)
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]

        // Assert
        XCTAssertNotNil(jsonObject)

        // Verify timestamp is in milliseconds
        let createdTimestamp = jsonObject?["created"] as? Int
        let expectedTimestamp = Int(date.timeIntervalSince1970 * 1000)
        XCTAssertEqual(createdTimestamp, expectedTimestamp, "Timestamp should be converted to milliseconds")
    }

    // MARK: - Edge Case Tests

    /// Test: Decode incomplete JSON (missing optional fields)
    func testDecodingWithMissingOptionalFields() throws {
        // Arrange - All fields in AppState are optional
        let jsonString = """
        {
            "source": "https://excalidraw.com",
            "files": {},
            "version": 2,
            "elements": [],
            "appState": {},
            "type": "excalidraw"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let file = try decoder.decode(ExcalidrawFile.self, from: jsonData)

        // Assert - Optional fields should be nil
        XCTAssertNil(file.appState.gridSize)
        XCTAssertNil(file.appState.viewBackgroundColor)
    }

    /// Test: Decode ExcalidrawFile with multiple ResourceFiles
    func testDecodingWithMultipleResourceFiles() throws {
        // Arrange
        let jsonString = """
        {
            "source": "https://excalidraw.com",
            "files": {
                "image1": {
                    "mimeType": "image/png",
                    "id": "image1",
                    "dataURL": "data:image/png;base64,abc"
                },
                "image2": {
                    "mimeType": "image/jpeg",
                    "id": "image2",
                    "dataURL": "data:image/jpeg;base64,xyz"
                }
            },
            "version": 2,
            "elements": [],
            "appState": {},
            "type": "excalidraw"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let file = try decoder.decode(ExcalidrawFile.self, from: jsonData)

        // Assert
        XCTAssertEqual(file.files.count, 2, "Should have two resource files")
        XCTAssertNotNil(file.files["image1"])
        XCTAssertNotNil(file.files["image2"])
        XCTAssertEqual(file.files["image1"]?.mimeType, "image/png")
        XCTAssertEqual(file.files["image2"]?.mimeType, "image/jpeg")
    }

    // MARK: - Performance Tests

    /// Test: Performance of encoding many ExcalidrawFile objects
    func testPerformanceOfEncoding() throws {
        // Arrange
        let file = ExcalidrawFile(
            source: "https://excalidraw.com",
            files: [:],
            version: 2,
            elements: [],
            appState: ExcalidrawFile.AppState(),
            type: "excalidraw"
        )
        let encoder = JSONEncoder()

        // Measure - Test execution time
        measure {
            // This closure will be executed multiple times, XCTest will calculate the average
            for _ in 0..<1000 {
                _ = try? encoder.encode(file)
            }
        }
    }
}
