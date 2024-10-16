//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
 
struct FileCheckpointRowView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState
    
    var checkpoint: FileCheckpoint
    
    @State private var file: ExcalidrawFile?
    
    var body: some View {
        Popover(arrowEdge: .trailing) {
            popoverContent()
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(checkpoint.filename ?? "")
                        .font(.headline)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    if let file {
                        Text("^[\(file.elements.count) elements](inflect: true)")
                    }
                    Text(" · ")
                    if let content = checkpoint.content {
                        Text("\(content.count.formatted(.byteCount(style: .file)))")
                    }
                    Text(" · ")
                    Text(checkpoint.updatedAt?.formatted() ?? "")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .buttonStyle(ListButtonStyle())
        .watchImmediately(of: checkpoint) { newValue in
            guard let content = newValue.content else { return }
            file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
        }
    }
    
    @MainActor @ViewBuilder
    private func popoverContent() -> some View {
        VStack(spacing: 12) {
            ZStack {
                if let data = checkpoint.content,
                   let file = try? JSONDecoder().decode(ExcalidrawFile.self, from: data),
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
        .padding(40)
        
    }
}


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: .preview)
        .environmentObject(FileState())
}
#endif
