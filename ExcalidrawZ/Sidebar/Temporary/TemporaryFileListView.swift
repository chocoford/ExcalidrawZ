//
//  TemporaryFileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct TemporaryFileListView: View {
    @Environment(FileState.self) private var fileState
    
    init(sortField: ExcalidrawFileSortField) {
        // self.sortField = sortField
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(fileState.temporaryFiles, id: \.self) { file in
                    TemporaryFileRowView(file: file)
                }
            }
            .animation(.default, value: fileState.temporaryFiles)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
#if os(macOS)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                            return
                        }
                        fileState.resetSelections()
                    }
            }
#endif
        }
        .suppressSidebarHoverWhileScrolling()
    }
}


#Preview {
    TemporaryFileListView(sortField: .name)
}
