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
//        VStack(alignment: .leading) {
//            HStack {
//                Text(checkpoint.filename ?? "")
//                    .font(.headline)
//                Spacer()
//            }
//            
//            HStack(spacing: 0) {
//                if let file {
//                    Text("^[\(file.elements.count) elements](inflect: true)")
//                }
//                Text(" · ")
//                if let content = checkpoint.content {
//                    Text("\(content.count.formatted(.byteCount(style: .file)))")
//                }
//                Text(" · ")
//                Text(checkpoint.updatedAt?.formatted() ?? "")
//            }
//            .font(.footnote)
//            .foregroundStyle(.secondary)
//        }
//        .lineLimit(1)
//        .padding(.horizontal, 4)
//        .padding(.vertical, 8)
//        .buttonStyle(ListButtonStyle())
//        .watchImmediately(of: checkpoint) { newValue in
//            guard let content = newValue.content else { return }
//            file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
//        }
        
        Popover(arrowEdge: .trailing) {
            FileCheckpointDetailView(checkpoint: checkpoint)
                .padding(40)
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
}


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: .preview)
        .environmentObject(FileState())
}
#endif
