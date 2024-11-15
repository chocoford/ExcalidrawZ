//
//  FileCheckpointDetailView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

struct FileCheckpointDetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState

    var checkpoint: FileCheckpoint
    
    init(checkpoint: FileCheckpoint) {
        self.checkpoint = checkpoint
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let data = checkpoint.content,
                   var file = try? ExcalidrawFile(data: data, id: checkpoint.file?.id),
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
                    let file = fileState.currentFile
                    file?.content = checkpoint.content
                    file?.name = checkpoint.filename
                    fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true)
                } label: {
                    Text(.localizable(.checkpointButtonRestore))
                }
                
                Button {
                    managedObjectContext.delete(checkpoint)
                } label: {
                    Text(.localizable(.checkpointButtonDelete))
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    FileCheckpointDetailView(checkpoint: .preview)
}
#endif
