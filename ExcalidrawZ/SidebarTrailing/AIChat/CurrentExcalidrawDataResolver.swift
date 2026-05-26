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
        let storedContent = try await storedContent(from: fileState)

        if let liveContent = try await resolveLiveSnapshot(
            canvasTarget: canvasTarget,
            baseContent: storedContent
        ) {
            return liveContent
        }

        return storedContent
    }

    @MainActor
    static func resolveLiveSnapshot(
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget,
        baseContent: Data?
    ) async throws -> Data? {
        guard let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget) else {
            return baseContent
        }

        let snapshot = try await coordinator.getCurrentFileSnapshot()
        if let snapshotData = snapshot.dataString.data(using: .utf8) {
            return try mergeLiveSceneData(snapshotData, into: baseContent)
        }

        return baseContent
    }

    private static func storedContent(from fileState: FileState) async throws -> Data? {
        switch fileState.currentActiveFile {
            case .file(let file):
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
                return try await FileCoordinator.shared.coordinatedRead(url: url)

            default:
                return nil
        }
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
