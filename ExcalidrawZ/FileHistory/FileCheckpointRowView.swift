//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
 
struct FileCheckpointRowView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState
    
    var checkpoint: FileCheckpoint
    
    var body: some View {
        Popover(arrowEdge: .trailing) {
            VStack(spacing: 12) {
                ExcalidrawImageView(data: checkpoint.content)
                    .frame(width: 400, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(spacing: 8) {
                    Text(checkpoint.filename ?? "Untitled")
                        .font(.title)
                    
                    Text(checkpoint.updatedAt?.formatted() ?? "")
                }
                
                HStack {
                    AsyncButton { @MainActor in
                        let file = fileState.currentFile
                        file?.content = checkpoint.content
                        file?.name = checkpoint.filename
                        try await fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true)
                    } label: {
                        Text("Restore")
                    }
                    
                    Button {
                        managedObjectContext.delete(checkpoint)
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .padding(40)
            
        } label: {
            HStack {
                Text(checkpoint.filename ?? "")
                    .font(.headline)
                Spacer()
                Text(checkpoint.updatedAt?.formatted() ?? "")
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .buttonStyle(ListButtonStyle())
    }
}


#if DEBUG
//#Preview {
//    FileCheckpointRowView(
//        store: .init(initialState: .init(checkpoint: .preview)) {
//            FileCheckpointRowStore()
//        }
//    )
//}
#endif
