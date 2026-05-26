//
//  AIMessageCheckpointLinkRepository.swift
//  ExcalidrawZ
//

import CoreData
import Foundation

enum AIMessageCheckpointLinkRole: String, Equatable, Sendable {
    case revertAnchor = "revert_anchor"
    case resultSnapshot = "result_snapshot"
}

enum AIMessageCheckpointKind: String, Equatable, Sendable {
    case file
    case local
}

struct AIMessageCheckpointLinkSnapshot: Sendable {
    let conversationID: String
    let messageID: String
    let role: AIMessageCheckpointLinkRole
    let checkpointID: UUID
    let checkpointKind: AIMessageCheckpointKind
    let fileScopeKind: String?
    let fileScopeID: String?
}

actor AIMessageCheckpointLinkRepository {
    func upsertLink(
        conversationID: String,
        messageID: String,
        role: AIMessageCheckpointLinkRole,
        checkpointID: UUID,
        checkpointKind: AIMessageCheckpointKind,
        fileScope: AIConversationFileScope?
    ) async throws {
        guard !conversationID.isEmpty, !messageID.isEmpty else { return }

        let context = PersistenceController.shared.newTaskContext()
        try await context.perform {
            let request = NSFetchRequest<AIMessageCheckpointLink>(entityName: "AIMessageCheckpointLink")
            request.predicate = NSPredicate(
                format: "conversationID == %@ AND messageID == %@ AND role == %@",
                conversationID,
                messageID,
                role.rawValue
            )
            request.fetchLimit = 1

            let link = try context.fetch(request).first ?? AIMessageCheckpointLink(context: context)
            if link.id == nil {
                link.id = UUID()
                link.createdAt = Date()
            }
            link.conversationID = conversationID
            link.messageID = messageID
            link.role = role.rawValue
            link.checkpointID = checkpointID
            link.checkpointKind = checkpointKind.rawValue
            link.fileScopeKind = fileScope?.kind.rawValue
            link.fileScopeID = fileScope?.id

            if context.hasChanges {
                try context.save()
            }
        }
    }

    func fetchLink(
        conversationID: String,
        messageID: String,
        role: AIMessageCheckpointLinkRole
    ) async throws -> AIMessageCheckpointLinkSnapshot? {
        guard !conversationID.isEmpty, !messageID.isEmpty else { return nil }

        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let request = NSFetchRequest<AIMessageCheckpointLink>(entityName: "AIMessageCheckpointLink")
            request.predicate = NSPredicate(
                format: "conversationID == %@ AND messageID == %@ AND role == %@",
                conversationID,
                messageID,
                role.rawValue
            )
            request.fetchLimit = 1
            return try context.fetch(request).first.flatMap(Self.snapshot(from:))
        }
    }

    func fetchLinks(
        conversationID: String,
        role: AIMessageCheckpointLinkRole,
        messageIDs: [String]
    ) async throws -> [String: AIMessageCheckpointLinkSnapshot] {
        guard !conversationID.isEmpty, !messageIDs.isEmpty else { return [:] }

        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let request = NSFetchRequest<AIMessageCheckpointLink>(entityName: "AIMessageCheckpointLink")
            request.predicate = NSPredicate(
                format: "conversationID == %@ AND role == %@ AND messageID IN %@",
                conversationID,
                role.rawValue,
                messageIDs
            )

            let links = try context.fetch(request).compactMap(Self.snapshot(from:))
            var result: [String: AIMessageCheckpointLinkSnapshot] = [:]
            for link in links {
                result[link.messageID] = link
            }
            return result
        }
    }

    func fetchLinkedMessageIDs(
        conversationID: String,
        role: AIMessageCheckpointLinkRole,
        messageIDs: [String]
    ) async throws -> Set<String> {
        Set(try await fetchLinks(
            conversationID: conversationID,
            role: role,
            messageIDs: messageIDs
        ).keys)
    }

    func deleteLinks(messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }

        let context = PersistenceController.shared.newTaskContext()
        try await context.perform {
            let request = NSFetchRequest<AIMessageCheckpointLink>(entityName: "AIMessageCheckpointLink")
            request.predicate = NSPredicate(format: "messageID IN %@", messageIDs)
            for link in try context.fetch(request) {
                context.delete(link)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func deleteLinks(conversationIDs: [String]) async throws {
        guard !conversationIDs.isEmpty else { return }

        let context = PersistenceController.shared.newTaskContext()
        try await context.perform {
            let request = NSFetchRequest<AIMessageCheckpointLink>(entityName: "AIMessageCheckpointLink")
            request.predicate = NSPredicate(format: "conversationID IN %@", conversationIDs)
            for link in try context.fetch(request) {
                context.delete(link)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private static func snapshot(
        from link: AIMessageCheckpointLink
    ) -> AIMessageCheckpointLinkSnapshot? {
        guard let conversationID = link.conversationID,
              let messageID = link.messageID,
              let roleRawValue = link.role,
              let role = AIMessageCheckpointLinkRole(rawValue: roleRawValue),
              let checkpointID = link.checkpointID,
              let checkpointKindRawValue = link.checkpointKind,
              let checkpointKind = AIMessageCheckpointKind(rawValue: checkpointKindRawValue)
        else {
            return nil
        }

        return AIMessageCheckpointLinkSnapshot(
            conversationID: conversationID,
            messageID: messageID,
            role: role,
            checkpointID: checkpointID,
            checkpointKind: checkpointKind,
            fileScopeKind: link.fileScopeKind,
            fileScopeID: link.fileScopeID
        )
    }
}
