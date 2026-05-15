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
        await documentSyncController.load(
            fileID: fileID.uuidString,
            data: data,
            force: force,
            validateCurrentParentFile: false
        )
    }
}
