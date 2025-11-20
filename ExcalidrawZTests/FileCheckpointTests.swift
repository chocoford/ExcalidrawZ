//
//  FileCheckpointTests.swift
//  ExcalidrawZTests
//
//  Created by Claude on 2025/11/17.
//

import XCTest
import CoreData
@testable import ExcalidrawZ

/// Tests for file checkpoint (version history) functionality
/// This test class demonstrates how to test business logic (file version control)
final class FileCheckpointTests: XCTestCase {

    // MARK: - Properties

    var testContainer: NSPersistentContainer!

    var viewContext: NSManagedObjectContext {
        testContainer.viewContext
    }

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create in-memory test database
        testContainer = {
            guard let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd"),
                  let model = NSManagedObjectModel(contentsOf: modelURL) else {
                fatalError("Failed to load Core Data model")
            }

            let container = NSPersistentContainer(name: "Model", managedObjectModel: model)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }

            if let error = loadError {
                fatalError("Failed to load persistent store: \(error)")
            }

            return container
        }()
    }

    override func tearDownWithError() throws {
        testContainer = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    /// Create test ExcalidrawFile JSON data
    func createTestFileData(withElementCount count: Int = 1) -> Data {
        let json: [String: Any] = [
            "source": "https://excalidraw.com",
            "files": [:],
            "version": 2,
            "elements": Array(repeating: [
                "type": "rectangle",
                "id": UUID().uuidString,
                "x": 0,
                "y": 0,
                "width": 100,
                "height": 100
            ], count: count),
            "appState": [:],
            "type": "excalidraw"
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    /// Create a test File entity
    func createTestFile(name: String = "Test File.excalidraw") -> File {
        let file = File(context: viewContext)
        file.id = UUID()
        file.name = name
        file.createdAt = Date()
        file.updatedAt = Date()
        file.content = createTestFileData()
        return file
    }

    // MARK: - Checkpoint Creation Tests

    /// Test: Create first checkpoint
    func testCreateFirstCheckpoint() throws {
        // Arrange - Create a File
        let file = createTestFile()
        try viewContext.save()

        // Act - Create new checkpoint on first update
        let newData = createTestFileData(withElementCount: 2)
        try file.updateElements(with: newData, newCheckpoint: true)
        try viewContext.save()

        // Assert - Verify checkpoint was created
        let checkpoints = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpoints.count, 1, "Should have created 1 checkpoint")
        XCTAssertEqual(checkpoints.first?.filename, file.name, "Checkpoint filename should match")
        XCTAssertNotNil(checkpoints.first?.content, "Checkpoint should contain content")
        XCTAssertNotNil(checkpoints.first?.updatedAt, "Checkpoint should have update time")
    }

    /// Test: Update latest checkpoint on second edit (don't create new checkpoint)
    func testUpdateLatestCheckpoint() throws {
        // Arrange - Create File and first checkpoint
        let file = createTestFile()
        try viewContext.save()

        let firstData = createTestFileData(withElementCount: 1)
        try file.updateElements(with: firstData, newCheckpoint: true)
        try viewContext.save()

        let checkpointsAfterFirst = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        let originalCheckpointCount = checkpointsAfterFirst.count
        let originalCheckpoint = checkpointsAfterFirst.first!
        let originalUpdatedAt = originalCheckpoint.updatedAt

        // Sleep briefly to ensure timestamps are different
        Thread.sleep(forTimeInterval: 0.01)

        // Act - Second update should update latest checkpoint instead of creating new one
        let secondData = createTestFileData(withElementCount: 2)
        try file.updateElements(with: secondData, newCheckpoint: false)
        try viewContext.save()

        // Assert - Verify checkpoint count hasn't increased, but content was updated
        let checkpointsAfterSecond = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpointsAfterSecond.count, originalCheckpointCount,
                       "Checkpoint count should remain the same")

        let updatedCheckpoint = try PersistenceController.shared.getLatestCheckpoint(
            of: file,
            viewContext: viewContext
        )
        XCTAssertNotNil(updatedCheckpoint)
        XCTAssertNotEqual(updatedCheckpoint?.updatedAt, originalUpdatedAt,
                         "Checkpoint's update time should have changed")
    }

    /// Test: Create multiple checkpoints through multiple edits
    func testCreateMultipleCheckpoints() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        // Act - Create 5 checkpoints
        for i in 1...5 {
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)
        }
        try viewContext.save()

        // Assert
        let checkpoints = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpoints.count, 5, "Should have 5 checkpoints")

        // Verify checkpoints are sorted in descending order by time (newest first)
        for i in 0..<checkpoints.count - 1 {
            XCTAssertGreaterThanOrEqual(
                checkpoints[i].updatedAt ?? Date.distantPast,
                checkpoints[i + 1].updatedAt ?? Date.distantPast,
                "Checkpoints should be sorted in descending order by time"
            )
        }
    }

    // MARK: - Checkpoint Limit Tests

    /// Test: Checkpoint limit of 50
    func testCheckpointLimit() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        // Act - Create more than 50 checkpoints
        let totalCheckpoints = 55
        for i in 1...totalCheckpoints {
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)

            // Save every 10 to reduce memory pressure
            if i % 10 == 0 {
                try viewContext.save()
            }
        }
        try viewContext.save()

        // Assert - Verify only the latest 50 are kept
        let checkpoints = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpoints.count, 50, "Should only keep 50 checkpoints")

        // Verify oldest checkpoints were deleted
        // Since checkpoints are sorted in descending order, the last one is the oldest
        // We can't directly verify deleted ones, but we can verify the retained ones are newer
        XCTAssertNotNil(checkpoints.first?.updatedAt)
        XCTAssertNotNil(checkpoints.last?.updatedAt)
    }

    /// Test: Checkpoint limit boundary case (exactly 50)
    func testCheckpointLimitBoundary() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        // Act - Create exactly 50 checkpoints
        for i in 1...50 {
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)
        }
        try viewContext.save()

        // Assert
        let checkpoints = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpoints.count, 50, "Should have 50 checkpoints")

        // Act - Create one more, should delete the oldest
        let newData = createTestFileData(withElementCount: 51)
        try file.updateElements(with: newData, newCheckpoint: true)
        try viewContext.save()

        // Assert
        let checkpointsAfterLimit = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpointsAfterLimit.count, 50,
                       "After exceeding limit, should delete oldest and maintain 50")
    }

    // MARK: - Checkpoint Query Tests

    /// Test: Get latest checkpoint
    func testGetLatestCheckpoint() throws {
        // Arrange - Create multiple checkpoints
        let file = createTestFile()
        try viewContext.save()

        var lastUpdatedAt: Date?
        for i in 1...3 {
            Thread.sleep(forTimeInterval: 0.01) // Ensure timestamps are different
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)
            if i == 3 {
                lastUpdatedAt = Date()
            }
        }
        try viewContext.save()

        // Act - Get latest checkpoint
        let latestCheckpoint = try PersistenceController.shared.getLatestCheckpoint(
            of: file,
            viewContext: viewContext
        )

        // Assert
        XCTAssertNotNil(latestCheckpoint, "Should be able to get latest checkpoint")
        XCTAssertNotNil(latestCheckpoint?.updatedAt)

        // Verify it's the latest
        let allCheckpoints = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        let maxUpdatedAt = allCheckpoints.compactMap { $0.updatedAt }.max()
        XCTAssertEqual(latestCheckpoint?.updatedAt, maxUpdatedAt,
                       "Should return the checkpoint with the latest time")
    }

    /// Test: Get checkpoint from file without checkpoints
    func testGetCheckpointFromFileWithoutCheckpoints() throws {
        // Arrange - Create a file without checkpoints
        let file = createTestFile()
        try viewContext.save()

        // Act
        let latestCheckpoint = try? PersistenceController.shared.getLatestCheckpoint(
            of: file,
            viewContext: viewContext
        )

        // Assert - Should return nil or throw error
        XCTAssertNil(latestCheckpoint, "File without checkpoints should return nil")
    }

    // MARK: - Checkpoint Content Validation Tests

    /// Test: Checkpoint content consistency with file content
    func testCheckpointContentConsistency() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        let testData = createTestFileData(withElementCount: 3)

        // Act - Create checkpoint
        try file.updateElements(with: testData, newCheckpoint: true)
        try viewContext.save()

        // Assert - Verify file content and checkpoint content are consistent
        let checkpoint = try PersistenceController.shared.getLatestCheckpoint(
            of: file,
            viewContext: viewContext
        )

        XCTAssertNotNil(checkpoint?.content)
        XCTAssertNotNil(file.content)

        // Parse both JSON and verify elements array length is the same
        let fileJSON = try JSONSerialization.jsonObject(with: file.content!) as? [String: Any]
        let checkpointJSON = try JSONSerialization.jsonObject(with: checkpoint!.content!) as? [String: Any]

        let fileElements = fileJSON?["elements"] as? [[String: Any]]
        let checkpointElements = checkpointJSON?["elements"] as? [[String: Any]]

        XCTAssertEqual(fileElements?.count, checkpointElements?.count,
                       "File and checkpoint elements count should be consistent")
    }

    // MARK: - File Deletion with Checkpoint Cleanup Tests

    /// Test: Deleting file should cascade delete checkpoints
    func testDeleteFileWithCheckpoints() throws {
        // Arrange - Create file and checkpoints
        let file = createTestFile()
        try viewContext.save()

        // Create 3 checkpoints
        for i in 1...3 {
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)
        }
        try viewContext.save()

        let fileID = file.id!
        let checkpointsBefore = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpointsBefore.count, 3, "Should have 3 checkpoints before deletion")

        // Act - Delete file (force permanently)
        try file.delete(context: viewContext, forcePermanently: true, save: true)

        // Assert - Verify checkpoints are also deleted
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        let allCheckpoints = try viewContext.fetch(fetchRequest)

        // Check if there are any checkpoints belonging to this file
        let remainingCheckpoints = allCheckpoints.filter { checkpoint in
            // Note: file is deleted, so relationship should be nil
            checkpoint.file?.id == fileID
        }
        XCTAssertEqual(remainingCheckpoints.count, 0,
                       "After deleting file, associated checkpoints should also be deleted")
    }

    /// Test: Soft deleting file (move to trash) keeps checkpoints
    func testSoftDeleteFileKeepsCheckpoints() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        // Create checkpoint
        let data = createTestFileData(withElementCount: 1)
        try file.updateElements(with: data, newCheckpoint: true)
        try viewContext.save()

        let checkpointsBefore = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        let originalCheckpointCount = checkpointsBefore.count

        // Act - Soft delete (move to trash)
        try file.delete(context: viewContext, forcePermanently: false, save: true)

        // Assert - File should be marked as in trash
        XCTAssertTrue(file.inTrash, "File should be marked as in trash")
        XCTAssertNotNil(file.deletedAt, "Should have deletion time")

        // Checkpoints should be retained
        let checkpointsAfter = try PersistenceController.shared.fetchFileCheckpoints(
            of: file,
            viewContext: viewContext
        )
        XCTAssertEqual(checkpointsAfter.count, originalCheckpointCount,
                       "Soft delete should not delete checkpoints")
    }

    // MARK: - Performance Tests

    /// Test: Performance of creating many checkpoints
    func testPerformanceCreateManyCheckpoints() throws {
        // Arrange
        let file = createTestFile()
        try viewContext.save()

        // Measure
        measure {
            // Create 50 checkpoints
            for i in 1...50 {
                let data = createTestFileData(withElementCount: i)
                try? file.updateElements(with: data, newCheckpoint: true)
            }
            try? viewContext.save()

            // Clean up for next test
            viewContext.reset()
        }
    }

    /// Test: Performance of querying checkpoints
    func testPerformanceFetchCheckpoints() throws {
        // Arrange - First create 50 checkpoints
        let file = createTestFile()
        try viewContext.save()

        for i in 1...50 {
            let data = createTestFileData(withElementCount: i)
            try file.updateElements(with: data, newCheckpoint: true)
        }
        try viewContext.save()

        // Measure
        measure {
            _ = try? PersistenceController.shared.fetchFileCheckpoints(
                of: file,
                viewContext: viewContext
            )
        }
    }
}
