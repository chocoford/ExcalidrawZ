import CoreData
import Foundation
import LLMCore
import LLMKit
import XCTest
@testable import ExcalidrawZ

final class AIConversationSchemeStorageTests: XCTestCase {
    func testPreviousModelPreservesHistoryAndAcceptsSchemeBinding() throws {
        let directory = try XCTUnwrap(Bundle(for: AIConversation.self).url(forResource: "Model", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model.mom")))
        let destination = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-Scheme.mom")))
        try SchemeStoreMigrationFixture.validate(source: source, destination: destination)
    }

    func testSchemeModelMigratesToInferenceUsageWithoutLosingHistory() throws {
        let directory = try XCTUnwrap(Bundle(for: AIConversation.self).url(forResource: "Model", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-Scheme.mom")))
        let destination = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-InferenceUsage.mom")))
        try SchemeStoreMigrationFixture.validate(source: source, destination: destination)
    }

    func testReleasedModelMigratesDirectlyToInferenceUsage() throws {
        let directory = try XCTUnwrap(Bundle(for: AIConversation.self).url(forResource: "Model", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model.mom")))
        let destination = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-InferenceUsage.mom")))
        try SchemeStoreMigrationFixture.validate(source: source, destination: destination)
    }

    func testInferenceUsageMigratesToProviderMetadata() throws {
        let directory = try XCTUnwrap(Bundle(for: AIConversation.self).url(forResource: "Model", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-InferenceUsage.mom")))
        let destination = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-ProviderMetadata.mom")))
        try SchemeStoreMigrationFixture.validate(source: source, destination: destination)
    }

    func testReleasedModelMigratesDirectlyToProviderMetadata() throws {
        let directory = try XCTUnwrap(Bundle(for: AIConversation.self).url(forResource: "Model", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model.mom")))
        let destination = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Model-ProviderMetadata.mom")))
        try SchemeStoreMigrationFixture.validate(source: source, destination: destination)
    }
}

/// A disposable SQLite fixture; never touches PersistenceController.shared or the user's store.
enum SchemeStoreMigrationFixture {
    static func validate(source: NSManagedObjectModel, destination: NSManagedObjectModel) throws {
        // Exercise schema migration independently of the app's generated managed-object classes.
        for model in [source, destination] {
            for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" }
        }
        guard destination.entitiesByName["AIConversation"]?.attributesByName["inferenceRouteData"]?.isOptional == true else {
            throw FixtureError.invalidModel
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldURL = directory.appendingPathComponent("old.sqlite")
        let newURL = directory.appendingPathComponent("new.sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: source)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: oldURL)
        let oldContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = oldCoordinator
        let conversation = NSEntityDescription.insertNewObject(forEntityName: "AIConversation", into: oldContext)
        conversation.setValue("legacy-conversation", forKey: "conversationID")
        let sourceHasRoute = source.entitiesByName["AIConversation"]?.attributesByName["inferenceRouteData"] != nil
        let savedRoute = try sourceHasRoute ? AIChatRouteStorage.encode(.init(
            selection: .init(schemeID: "excalidraw-canvas", profileID: "extra-high"), billing: .platform)) : nil
        if sourceHasRoute { conversation.setValue(savedRoute, forKey: "inferenceRouteData") }
        let message = NSEntityDescription.insertNewObject(forEntityName: "AIConversationMessage", into: oldContext)
        message.setValue("retained history", forKey: "content")
        message.setValue(12.5, forKey: "usageConsumed")
        message.setValue(conversation, forKey: "conversation")
        let records: [LLMInferenceUsage] = [
            .init(id: "usage-1", generationID: "generation", billingSource: .byok,
                  tokens: .init(promptTokens: 100, completionTokens: 20, totalTokens: 120), isComplete: true,
                  providerToolUsage: ["web_search_requests": 2]),
            .init(id: "usage-2", generationID: "generation", billingSource: .byok)
        ]
        let sourceHasUsage = source.entitiesByName["AIConversationMessage"]?.attributesByName["inferenceUsageData"] != nil
        if sourceHasUsage { message.setValue(try AIInferenceUsageStorage.encode(records), forKey: "inferenceUsageData") }
        try oldContext.save()
        oldContext.reset()
        try oldCoordinator.remove(oldStore)

        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: source, destinationModel: destination)
        let migration = NSMigrationManager(sourceModel: source, destinationModel: destination)
        try migration.migrateStore(from: oldURL, sourceType: NSSQLiteStoreType, options: nil, with: mapping,
                                   toDestinationURL: newURL, destinationType: NSSQLiteStoreType, destinationOptions: nil)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destination)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: newURL)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversation"))
        guard rows.count == 1, let row = rows.first,
              row.value(forKey: "conversationID") as? String == "legacy-conversation",
              row.value(forKey: "inferenceRouteData") as? Data == savedRoute,
              let messages = row.value(forKey: "messages") as? Set<NSManagedObject>, messages.count == 1,
              messages.first?.value(forKey: "content") as? String == "retained history",
              messages.first?.value(forKey: "usageConsumed") as? Double == 12.5 else {
            throw FixtureError.historyChanged
        }
        let binding = LLMSchemeConversationBinding(
            selection: .init(schemeID: "excalidraw-canvas", profileID: "extra-high"), billing: .platform
        )
        row.setValue(try AIChatRouteStorage.encode(binding), forKey: "inferenceRouteData")
        try context.save()
        context.reset()
        let restored = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversation"))
        guard let data = restored.first?.value(forKey: "inferenceRouteData") as? Data,
              try AIChatRouteStorage.decode(data) == binding else { throw FixtureError.bindingChanged }
        let direct = AIDirectConversationRecord(connectionID: "saved-provider", binding: .init(
            configuration: .openAI, chatModel: .other("provider-model")))
        restored.first?.setValue(try AIChatRouteStorage.encodeDirect(direct), forKey: "inferenceRouteData")
        try context.save()
        context.reset()
        let directRows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversation"))
        guard let directData = directRows.first?.value(forKey: "inferenceRouteData") as? Data,
              try AIChatRouteStorage.decodeDirect(directData) == direct,
              try AIChatRouteStorage.decode(directData) == nil else { throw FixtureError.bindingChanged }

        if destination.entitiesByName["AIConversationMessage"]?.attributesByName["inferenceUsageData"] != nil {
            let messageRows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversationMessage"))
            guard let message = messageRows.first,
                  AIInferenceUsageStorage.decode(message.value(forKey: "inferenceUsageData") as? Data) == (sourceHasUsage ? records : nil) else { throw FixtureError.bindingChanged }
            message.setValue(try AIInferenceUsageStorage.encode(records), forKey: "inferenceUsageData")
            try context.save()
            context.reset()
            let reloaded = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversationMessage"))
            let restored = AIInferenceUsageStorage.decode(reloaded.first?.value(forKey: "inferenceUsageData") as? Data)
            guard restored == records, restored?.last?.tokens == nil,
                  reloaded.first?.value(forKey: "content") as? String == "retained history",
                  reloaded.first?.value(forKey: "usageConsumed") as? Double == 12.5 else { throw FixtureError.bindingChanged }
        }

        if destination.entitiesByName["AIConversationMessage"]?.attributesByName["citationsData"] != nil {
            let messages = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversationMessage"))
            guard let message = messages.first, message.value(forKey: "citationsData") == nil else { throw FixtureError.historyChanged }
            let sources = [LLMSourceCitation(url: URL(string: "https://sources.example/article")!, title: "Provider source")]
            message.setValue(try AISourceCitationStorage.encode(sources), forKey: "citationsData")
            try context.save()
            context.reset()
            let reloaded = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AIConversationMessage"))
            guard AISourceCitationStorage.decode(reloaded.first?.value(forKey: "citationsData") as? Data) == sources,
                  AIInferenceUsageStorage.decode(reloaded.first?.value(forKey: "inferenceUsageData") as? Data) == records,
                  reloaded.first?.value(forKey: "content") as? String == "retained history" else { throw FixtureError.historyChanged }
        }
    }

    enum FixtureError: Error { case invalidModel, historyChanged, bindingChanged }
}
