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
        if let liveContent = liveContent(from: fileState, canvasTarget: canvasTarget) {
            return liveContent
        }

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

    @MainActor
    private static func liveContent(
        from fileState: FileState,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    ) -> Data? {
        let coordinator: ExcalidrawCanvasView.Coordinator? = switch canvasTarget {
            case .normal:
                fileState.excalidrawWebCoordinator
            case .collaboration:
                fileState.excalidrawCollaborationWebCoordinator
        }

        return coordinator?.parent?.file?.content
    }
}
