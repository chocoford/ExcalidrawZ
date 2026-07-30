//
//  PresentationConfigurationRepository.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import CoreData
import Foundation

enum ExcalidrawPresentationFileReference: Hashable, Sendable {
    case libraryFile(objectURI: URL)
    case collaborationFile(objectURI: URL)
}

actor PresentationConfigurationRepository {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func load(
        for reference: ExcalidrawPresentationFileReference
    ) async throws -> ExcalidrawPresentationConfiguration {
        let data = try await presentationData(for: reference)
        guard let data else {
            return ExcalidrawPresentationConfiguration()
        }
        return try decoder.decode(
            ExcalidrawPresentationConfiguration.self,
            from: data
        )
    }

    func save(
        _ configuration: ExcalidrawPresentationConfiguration,
        for reference: ExcalidrawPresentationFileReference
    ) async throws {
        let data = try encoder.encode(configuration)
        let context = PersistenceController.shared.newTaskContext()

        try await context.perform {
            let object = try self.managedObject(
                for: reference,
                in: context
            )

            switch (reference, object) {
                case (.libraryFile, let file as File):
                    guard file.presentationData != data else { return }
                    file.presentationData = data

                case (.collaborationFile, let file as CollaborationFile):
                    guard file.presentationData != data else { return }
                    file.presentationData = data

                default:
                    throw PresentationConfigurationRepositoryError.invalidObjectType
            }

            try context.save()
        }
    }

    private func presentationData(
        for reference: ExcalidrawPresentationFileReference
    ) async throws -> Data? {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let object = try self.managedObject(
                for: reference,
                in: context
            )

            return switch (reference, object) {
                case (.libraryFile, let file as File):
                    file.presentationData
                case (.collaborationFile, let file as CollaborationFile):
                    file.presentationData
                default:
                    throw PresentationConfigurationRepositoryError.invalidObjectType
            }
        }
    }

    private nonisolated func managedObject(
        for reference: ExcalidrawPresentationFileReference,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        let objectURI = switch reference {
            case .libraryFile(let objectURI),
                 .collaborationFile(let objectURI):
                objectURI
        }

        guard let objectID = context.persistentStoreCoordinator?
            .managedObjectID(forURIRepresentation: objectURI) else {
            throw PresentationConfigurationRepositoryError.fileNotFound
        }
        return try context.existingObject(with: objectID)
    }
}

private enum PresentationConfigurationRepositoryError: LocalizedError {
    case fileNotFound
    case invalidObjectType

    var errorDescription: String? {
        switch self {
            case .fileNotFound:
                "The presentation file could not be found."
            case .invalidObjectType:
                "The presentation metadata is attached to an unsupported file type."
        }
    }
}
