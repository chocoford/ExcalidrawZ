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
              let data = file?.content else { return }
        guard await waitUntilReadyForFileLoad(fileID: fileID.uuidString) else { return }
        do {
            try await self.webActor.loadFile(id: fileID.uuidString, data: data, force: force)
        } catch {
            self.publishError(error)
        }
    }
}
