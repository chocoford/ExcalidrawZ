//
//  FileHistorySettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

struct FileHistorySettingsView: View {
    @Environment(FileState.self) private var fileState
    
    @State private var currentCheckpoint: FileCheckpoint?
    
    var body: some View {
        
        if case .file(let currentFile) = fileState.currentActiveFile {
            HStack {
                FileCheckpointListView(file: currentFile/*, selection: $currentCheckpoint*/)
                if let currentCheckpoint {
                    FileCheckpointDetailView(checkpoint: currentCheckpoint)
                } else {
                    Text("Select a file checkpoint.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        
    }
}

#Preview {
    FileHistorySettingsView()
        .environment(FileState())
}
