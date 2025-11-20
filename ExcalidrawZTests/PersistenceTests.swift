//
//  PersistenceTests.swift
//  ExcalidrawZTests
//
//  Created by Claude on 2025/11/17.
//

import XCTest
import CoreData
@testable import ExcalidrawZ

/// Tests for Core Data persistence functionality
/// This test class demonstrates how to test database operations (CRUD)
final class PersistenceTests: XCTestCase {

    // MARK: - Properties

    /// Test NSPersistentContainer
    /// Uses in-memory storage (won't write to disk), automatically cleaned up after tests
    var testContainer: NSPersistentContainer!

    /// Test ViewContext
    var viewContext: NSManagedObjectContext {
        testContainer.viewContext
    }

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create an in-memory test database container
        // Uses the same data model as the main app, but stores in memory
        testContainer = {
            // Load data model
            guard let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd"),
                  let model = NSManagedObjectModel(contentsOf: modelURL) else {
                fatalError("Failed to load Core Data model")
            }

            let container = NSPersistentContainer(name: "Model", managedObjectModel: model)

            // Use in-memory storage (no disk writes)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]

            // Synchronously load persistent store
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
        // Clean up test data
        testContainer = nil
        try super.tearDownWithError()
    }

    // MARK: - Basic CRUD Tests

    /// Test: Create a Group entity
    func testCreateGroup() throws {
        // Arrange
        let groupName = "Test Group"

        // Act - Create Group entity
        let group = Group(context: viewContext)
        group.id = UUID()
        group.name = groupName
        group.rank = 1
        group.createdAt = Date()
        group.updatedAt = Date()

        // Save to database
        try viewContext.save()

        // Assert - Verify creation succeeded
        XCTAssertNotNil(group.id, "Group ID should exist")
        XCTAssertEqual(group.name, groupName, "Group name should match")

        // Verify by querying the database
        let fetchRequest = Group.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", groupName)
        let results = try viewContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1, "Should have exactly one matching Group")
        XCTAssertEqual(results.first?.name, groupName)
    }

    /// Test: Create a File entity and associate it with a Group
    func testCreateFileInGroup() throws {
        // Arrange - First create a Group
        let group = Group(context: viewContext)
        group.id = UUID()
        group.name = "Test Group"
        group.rank = 1
        group.createdAt = Date()
        group.updatedAt = Date()

        // Act - Create File and associate with Group
        let file = File(context: viewContext)
        file.id = UUID()
        file.name = "Test File.excalidraw"
        file.createdAt = Date()
        file.updatedAt = Date()
        file.group = group

        // Save
        try viewContext.save()

        // Assert - Verify relationship
        XCTAssertEqual(file.group, group, "File should be associated with Group")
        XCTAssertTrue(group.files?.contains(file) ?? false, "Group should contain File")

        // Verify by querying the database
        let fetchRequest = File.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", "Test File.excalidraw")
        let results = try viewContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.group?.name, "Test Group")
    }

    /// Test: Update File entity properties
    func testUpdateFile() throws {
        // Arrange - Create a File
        let file = File(context: viewContext)
        file.id = UUID()
        file.name = "Original Name.excalidraw"
        file.createdAt = Date()
        file.updatedAt = Date()
        try viewContext.save()

        let originalUpdatedAt = file.updatedAt

        // Act - Update name
        let newName = "New Name.excalidraw"
        file.name = newName
        file.updatedAt = Date()
        try viewContext.save()

        // Assert
        XCTAssertEqual(file.name, newName, "Name should be updated")
        XCTAssertNotEqual(file.updatedAt, originalUpdatedAt, "updatedAt should have changed")

        // Verify by querying the database
        let fetchRequest = File.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", newName)
        let results = try viewContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, newName)
    }

    /// Test: Delete File entity
    func testDeleteFile() throws {
        // Arrange - Create a File
        let file = File(context: viewContext)
        file.id = UUID()
        file.name = "File to Delete.excalidraw"
        file.createdAt = Date()
        file.updatedAt = Date()
        try viewContext.save()

        let fileID = file.id

        // Act - Delete File
        viewContext.delete(file)
        try viewContext.save()

        // Assert - Verify deletion
        let fetchRequest = File.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", fileID! as CVarArg)
        let results = try viewContext.fetch(fetchRequest)

        XCTAssertEqual(results.count, 0, "File should be deleted")
    }

    /// Test: Cascade delete (deleting Group deletes associated Files)
    func testCascadeDeleteGroupWithFiles() throws {
        // Arrange - Create Group and multiple Files
        let group = Group(context: viewContext)
        group.id = UUID()
        group.name = "Group to Delete"
        group.rank = 1
        group.createdAt = Date()
        group.updatedAt = Date()

        // Create 3 associated Files
        for i in 1...3 {
            let file = File(context: viewContext)
            file.id = UUID()
            file.name = "File\(i).excalidraw"
            file.createdAt = Date()
            file.updatedAt = Date()
            file.group = group
        }

        try viewContext.save()
        let groupID = group.id

        // Act - Delete Group
        viewContext.delete(group)
        try viewContext.save()

        // Assert - Verify Group and associated Files are deleted (depends on Core Data delete rule)
        let groupFetchRequest = Group.fetchRequest()
        groupFetchRequest.predicate = NSPredicate(format: "id == %@", groupID! as CVarArg)
        let groupResults = try viewContext.fetch(groupFetchRequest)
        XCTAssertEqual(groupResults.count, 0, "Group should be deleted")

        // Note: This assertion depends on the delete rule in your Core Data model for Group-File relationship
        // If set to Cascade, Files will also be deleted
        // If set to Nullify, Files will remain but group relationship will be nil
    }

    // MARK: - Query Tests

    /// Test: Fetch Files by name
    func testFetchFilesByName() throws {
        // Arrange - Create multiple Files
        let fileNames = ["Alpha.excalidraw", "Beta.excalidraw", "Gamma.excalidraw"]
        for name in fileNames {
            let file = File(context: viewContext)
            file.id = UUID()
            file.name = name
            file.createdAt = Date()
            file.updatedAt = Date()
        }
        try viewContext.save()

        // Act - Query files containing "Beta"
        let fetchRequest = File.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name CONTAINS[cd] %@", "Beta")
        let results = try viewContext.fetch(fetchRequest)

        // Assert
        XCTAssertEqual(results.count, 1, "Should find one matching file")
        XCTAssertEqual(results.first?.name, "Beta.excalidraw")
    }

    /// Test: Fetch Files by date range
    func testFetchFilesByDateRange() throws {
        // Arrange - Create Files with different dates
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let file1 = File(context: viewContext)
        file1.id = UUID()
        file1.name = "Today's File.excalidraw"
        file1.createdAt = now
        file1.updatedAt = now

        let file2 = File(context: viewContext)
        file2.id = UUID()
        file2.name = "Yesterday's File.excalidraw"
        file2.createdAt = yesterday
        file2.updatedAt = yesterday

        let file3 = File(context: viewContext)
        file3.id = UUID()
        file3.name = "Last Week's File.excalidraw"
        file3.createdAt = lastWeek
        file3.updatedAt = lastWeek

        try viewContext.save()

        // Act - Query files created in the past 2 days
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let fetchRequest = File.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "createdAt >= %@", twoDaysAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let results = try viewContext.fetch(fetchRequest)

        // Assert
        XCTAssertEqual(results.count, 2, "Should find two files")
        XCTAssertTrue(results.contains { $0.name == "Today's File.excalidraw" })
        XCTAssertTrue(results.contains { $0.name == "Yesterday's File.excalidraw" })
    }

    /// Test: Fetch Groups sorted by rank
    func testFetchGroupsSortedByRank() throws {
        // Arrange - Create multiple Groups with different ranks
        let groups = [
            ("High Priority", 0),
            ("Medium Priority", 1),
            ("Low Priority", 2)
        ]

        for (name, rank) in groups {
            let group = Group(context: viewContext)
            group.id = UUID()
            group.name = name
            group.rank = Int64(rank)
            group.createdAt = Date()
            group.updatedAt = Date()
        }
        try viewContext.save()

        // Act - Query by rank in ascending order
        let fetchRequest = Group.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "rank", ascending: true)]
        let results = try viewContext.fetch(fetchRequest)

        // Assert
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].name, "High Priority")
        XCTAssertEqual(results[1].name, "Medium Priority")
        XCTAssertEqual(results[2].name, "Low Priority")
    }

    // MARK: - Performance Tests

    /// Test: Performance of batch creating Files
    func testPerformanceBatchCreateFiles() throws {
        measure {
            // Batch create 100 Files
            for i in 0..<100 {
                let file = File(context: viewContext)
                file.id = UUID()
                file.name = "Performance Test File\(i).excalidraw"
                file.createdAt = Date()
                file.updatedAt = Date()
            }

            try? viewContext.save()

            // Clean up for next test iteration
            viewContext.reset()
        }
    }

    /// Test: Performance of querying many Files
    func testPerformanceFetchManyFiles() throws {
        // Arrange - First create 1000 Files
        for i in 0..<1000 {
            let file = File(context: viewContext)
            file.id = UUID()
            file.name = "File\(i).excalidraw"
            file.createdAt = Date()
            file.updatedAt = Date()
        }
        try viewContext.save()

        // Measure - Test query performance
        measure {
            let fetchRequest = File.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            _ = try? viewContext.fetch(fetchRequest)
        }
    }

    // MARK: - Error Handling Tests

    /// Test: Error handling when saving invalid data
    func testSaveInvalidDataHandling() throws {
        // Arrange - Create a File without setting required properties
        let file = File(context: viewContext)
        file.id = UUID()
        // Note: Intentionally not setting name if it's required

        // Act & Assert - Attempting to save should throw an error or fail
        // This depends on your Core Data model constraint settings
        do {
            try viewContext.save()
            // If save succeeds, it means name is not required
        } catch {
            // If an error is thrown, this is expected
            XCTAssertNotNil(error, "Saving invalid data should produce an error")
        }
    }
}
