//
//  Coordinator+Persisitence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation

extension ExcalidrawCore {
    func loadFile(from file: File?, force: Bool = false) {
        guard !self.isLoading, !self.webView.isLoading else { return }
        guard let fileID = file?.id,
            let data = file?.content else { return }
        Task.detached {
            do {
                try await self.webActor.loadFile(id: fileID.uuidString, data: data, force: force)
            } catch {
                self.publishError(error)
            }
        }
    }
}
