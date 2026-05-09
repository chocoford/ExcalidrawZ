//
//  FileState+History.swift
//  ExcalidrawZ
//
//  Shared file-history restore helpers.
//

import Foundation

extension FileState {
    @MainActor
    func restoreActiveCanvas(
        fromCheckpointContent content: Data,
        filename: String?
    ) async throws {
        switch currentActiveFile {
            case .file(let file):
                file.content = content
                if let filename {
                    file.name = filename
                }
                await excalidrawWebCoordinator?.loadFile(from: file, force: true)
                didUpdateFile = false

            case .localFile(let fileURL):
                guard case .localFolder(let folder) = currentActiveGroup else {
                    throw AIChatEditError.unsupportedFile
                }

                var parsedFile = try ExcalidrawFile(data: content)
                parsedFile.id = ExcalidrawFile.localFileURLIDMapping[fileURL] ?? UUID().uuidString

                try await folder.withSecurityScopedURL { _ in
                    try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: content)
                }

                await excalidrawWebCoordinator?.loadFile(from: parsedFile, force: true)
                didUpdateFile = false

            case .temporaryFile, .collaborationFile, nil:
                throw AIChatEditError.unsupportedFile
        }
    }
}
