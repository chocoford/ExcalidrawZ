//
//  Coordinator+Persisitence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation

extension ExcalidrawCore {
    func loadFile(from file: File?, force: Bool = false) async {
        guard let fileID = file?.id,
              let data = file?.content else {
            logLoadFileDiag(logger, "[LoadFileDiag] coreDataLoad skipped: missing file id or content", level: .warning)
            return
        }
        guard await waitUntilReadyForFileLoad(fileID: fileID.uuidString) else {
            logLoadFileDiag(logger, "[LoadFileDiag] coreDataLoad notReady id=\(fileID.uuidString)", level: .warning)
            return
        }
        do {
            try await self.webActor.loadFile(id: fileID.uuidString, data: data, force: force)
        } catch {
            self.publishError(error)
        }
    }
}
