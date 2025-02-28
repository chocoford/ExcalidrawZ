//
//  FileCheckpointDetailView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

struct FileCheckpointDetailView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var fileState: FileState

    var checkpoint: Checkpoint
    
    init(checkpoint: Checkpoint) {
        self.checkpoint = checkpoint
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let data = checkpoint.content,
                   let file = try? ExcalidrawFile(data: data, id: checkpoint.fileID),
                   !file.elements.isEmpty {
                    ExcalidrawRenderer(file: file)
                } else {
                    if colorScheme == .light {
                        Color.white
                    } else {
                        Color.black
                    }
                }
            }
            .frame(width: 400, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(spacing: 8) {
                Text(checkpoint.filename ?? "")
                    .font(.title)
                
                Text(checkpoint.updatedAt?.formatted() ?? "")
            }
            
            HStack {
                Button { @MainActor in
                    restoreCheckpoint()
                } label: {
                    Text(.localizable(.checkpointButtonRestore))
                }
                
                Button {
                    viewContext.delete(checkpoint)
                    dismiss()
                } label: {
                    Text(.localizable(.checkpointButtonDelete))
                }
            }
        }
    }
    
    private func restoreCheckpoint() {
        guard let content = checkpoint.content else { return }
        if checkpoint.fileID != nil {
            let file = fileState.currentFile
            file?.content = checkpoint.content
            file?.name = checkpoint.filename
            fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true)
        } else if let folder = fileState.currentLocalFolder,
                  let fileURL = fileState.currentLocalFile {
            do {
                try folder.withSecurityScopedURL { scopedURL in
                    var file = try ExcalidrawFile(data: content)
                    file.id = ExcalidrawFile.localFileURLIDMapping[fileURL] ?? UUID()
                    fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true)
                    try content.write(to: fileURL)
                }
            } catch {
                alertToast(error)
            }
        }
        fileState.didUpdateFile = false
        dismiss()
    }
}

#if DEBUG
#Preview {
    FileCheckpointDetailView(checkpoint: FileCheckpoint.preview)
}
#endif
