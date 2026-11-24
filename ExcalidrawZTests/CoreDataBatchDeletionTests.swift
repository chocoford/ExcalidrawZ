@preconcurrency import CoreData
import XCTest
@testable import ExcalidrawZ

@MainActor
final class CoreDataBatchDeletionTests: XCTestCase {
    func testRemovingReferenceUpdatesFetchedSidebarRowsWithoutAnotherContextSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let entity = NSEntityDescription()
        entity.name = "LocalFolder"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        let parent = NSRelationshipDescription()
        parent.name = "parent"
        parent.destinationEntity = entity
        parent.maxCount = 1
        parent.deleteRule = .nullifyDeleteRule
        let children = NSRelationshipDescription()
        children.name = "children"
        children.destinationEntity = entity
        children.maxCount = 0
        children.deleteRule = .nullifyDeleteRule
        parent.inverseRelationship = children
        children.inverseRelationship = parent
        entity.properties = [name, parent, children]
        let model = NSManagedObjectModel()
        model.entities = [entity]

        let container = NSPersistentContainer(name: "RemovalRegression", managedObjectModel: model)
        let store = NSPersistentStoreDescription(url: directory.appendingPathComponent("Folders.sqlite"))
        store.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [store]
        var storeError: Error?
        container.loadPersistentStores { _, error in storeError = error }
        if let storeError { throw storeError }
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }

        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        let worker = container.newBackgroundContext()
        let (removedIDs, survivingID) = try await worker.perform {
            let root = NSManagedObject(entity: entity, insertInto: worker)
            root.setValue("Projects", forKey: "name")
            let child = NSManagedObject(entity: entity, insertInto: worker)
            child.setValue("Sources", forKey: "name")
            child.setValue(root, forKey: "parent")
            let grandchild = NSManagedObject(entity: entity, insertInto: worker)
            grandchild.setValue("Drawings", forKey: "name")
            grandchild.setValue(child, forKey: "parent")
            let independentRoot = NSManagedObject(entity: entity, insertInto: worker)
            independentRoot.setValue("Independent reference", forKey: "name")
            try worker.save()
            return ([root.objectID, child.objectID, grandchild.objectID], independentRoot.objectID)
        }

        // Match the pinned UI context and keep expanded descendants registered.
        try viewContext.setQueryGenerationFrom(.current)
        let displayedObjects = try viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "LocalFolder"))
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocalFolder")
        request.predicate = NSPredicate(format: "parent == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let rows = NSFetchedResultsController(fetchRequest: request, managedObjectContext: viewContext,
                                             sectionNameKeyPath: nil, cacheName: nil)
        // Fetched-results controllers only track changes while they have a delegate.
        let observer = FetchedRowsObserver()
        rows.delegate = observer
        try rows.performFetch()
        XCTAssertEqual(rows.fetchedObjects?.count, 2)

        try await worker.perform {
            // Only IDs cross the lookup/cancellation boundary. The deletion
            // worker may no longer retain any fetched objects to save afterward.
            worker.reset()
            try worker.executeAndMergeChanges(using: NSBatchDeleteRequest(objectIDs: removedIDs),
                                              mergingInto: [viewContext])
        }
        await viewContext.perform { viewContext.processPendingChanges() }

        XCTAssertEqual(rows.fetchedObjects?.map(\.objectID), [survivingID])
        XCTAssertGreaterThan(observer.changes, 0)
        for object in displayedObjects where removedIDs.contains(object.objectID) {
            XCTAssertTrue(object.isDeleted || object.managedObjectContext == nil)
        }
        let remainingCount = try await worker.perform {
            try worker.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "LocalFolder"))
        }
        XCTAssertEqual(remainingCount, 1)
    }

    private final class FetchedRowsObserver: NSObject, NSFetchedResultsControllerDelegate {
        var changes = 0
        func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
            changes += 1
        }
    }
}
