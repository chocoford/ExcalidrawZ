//
//  CurrentExcalidrawDataResolver.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation

enum CurrentExcalidrawDataResolver {
    @MainActor
    static func resolve(
        fileState: FileState,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) async throws -> Data? {
        let currentFileID = currentFileID(from: fileState.currentActiveFile)
        let storedContent = try await storedContent(from: fileState)

        if let liveContent = try await resolveLiveSnapshot(
            canvasTarget: canvasTarget,
            baseContent: storedContent,
            currentFileID: currentFileID
        ) {
            return liveContent
        }

        return storedContent
    }

    @MainActor
    static func resolveLiveSnapshot(
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget,
        baseContent: Data?,
        currentFileID: UUID? = nil
    ) async throws -> Data? {
        try await LockedContentAIGuard.ensureAIReadable(
            canvasTarget: canvasTarget,
            currentFileID: currentFileID
        )
        let coordinator = try await ExcalidrawCoordinatorRegistry.shared.resolvedCoordinator(for: canvasTarget)
        let resolvedBaseContent = resolvedBaseContent(for: canvasTarget, provided: baseContent)
        guard let coordinator else {
            return resolvedBaseContent
        }

        let snapshot = try await coordinator.getCurrentFileSnapshot()
        return try mergeLiveSceneData(snapshot.documentData(), into: resolvedBaseContent)
    }

    private static func resolvedBaseContent(
        for canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget,
        provided baseContent: Data?
    ) -> Data? {
        baseContent ?? (canvasTarget.targetsProposalCanvas ? AIProposalSandbox.blankFileData() : nil)
    }

    @MainActor
    private static func storedContent(from fileState: FileState) async throws -> Data? {
        switch fileState.currentActiveFile {
            case .file(let file):
                try await LockedContentAIGuard.ensureAIReadable(fileObjectID: file.objectID)
                if let content = file.content {
                    return content
                }
                return try await file.loadContent()

            case .collaborationFile(let room):
                if let content = room.content {
                    return content
                }
                return try await room.loadContent()

            case .localFile(let url), .temporaryFile(let url):
                return try await FileSyncCoordinator.shared.openFile(url)

            case .cloudStorageFile(let reference):
                return try await CloudStorageDocumentStore.shared.content(
                    for: reference,
                    checkingRemoteRevision: false
                )

            default:
                return nil
        }
    }

    @MainActor
    private static func currentFileID(from activeFile: FileState.ActiveFile?) -> UUID? {
        if case .file(let file) = activeFile {
            return file.id
        }
        return nil
    }

    private static func mergeLiveSceneData(_ sceneData: Data, into baseData: Data?) throws -> Data {
        guard let baseData,
              var baseObject = try JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let sceneObject = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any] else {
            return sceneData
        }

        for key in ["elements", "files", "appState"] {
            if let value = sceneObject[key] {
                baseObject[key] = value
            }
        }
        return try JSONSerialization.data(withJSONObject: baseObject)
    }
}
