//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI

struct FileCheckpointRowView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @Environment(\.colorScheme) var colorScheme
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState
    
    var checkpoint: Checkpoint
    
    @State private var file: ExcalidrawFile?
    
    var body: some View {
        content()
            .watchImmediately(of: checkpoint) { newValue in
                guard let content = newValue.content else { return }
                file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
#if os(iOS)
            NavigationLink {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
#elseif os(macOS)
            Popover(arrowEdge: .trailing) {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
            .buttonStyle(
                ExcalidrawZSidebarRowButtonStyle(isSelected: false, isMultiSelected: false)
            )
//            .buttonStyle(ListButtonStyle())
#endif
    }
    
    @MainActor @ViewBuilder
    private func label() -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text((checkpoint.filename ?? "")/* + " - \(checkpoint.objectID)"*/)
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 0) {
                if let file {
                    if #available(macOS 13.0, iOS 16.0, *) {
                        Text(.localizable(.checkpointsElementsDescription(file.elements.count)))
                    } else {
                        Text(file.elements.count.formatted())
                    }
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
}


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: FileCheckpoint.preview)
        .environmentObject(FileState())
}
#endif
