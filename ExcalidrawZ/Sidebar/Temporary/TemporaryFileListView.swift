//
//  TemporaryFileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI

import ChocofordUI

struct TemporaryFileListView: View {
    @EnvironmentObject private var fileState: FileState
    
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
        }
    }
}

struct TemporaryFileRowView: View {
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    var file: URL
    
    @State private var modifiedDate: Date = .distantPast
    
    var body: some View {
        Button {
            fileState.currentTemporaryFile = file
        } label: {
            FileRowLabel(
                name: file.deletingPathExtension().lastPathComponent,
                updatedAt: modifiedDate
            )
        }
        .buttonStyle(ListButtonStyle(selected: fileState.currentTemporaryFile == file))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .watchImmediately(of: file) { newValue in
            updateModifiedDate()
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        Button {
            fileState.currentTemporaryFile = nil
            fileState.temporaryFiles.removeAll(where: {$0 == file})
            
            if fileState.temporaryFiles.isEmpty {
                fileState.isTemporaryGroupSelected = false
            } else {
                fileState.currentTemporaryFile = fileState.temporaryFiles.first
            }
        } label: {
            Label(.localizable(.sidebarTemporaryFileRowContextMenuCloseFile), systemSymbol: .xmarkCircle)
        }
    }
    
    private func updateModifiedDate() {
        self.modifiedDate = .distantPast
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.filePath)
            if let modifiedDate = attributes[FileAttributeKey.modificationDate] as? Date {
                self.modifiedDate = modifiedDate
            }
        } catch {
            print(error)
            DispatchQueue.main.async {
                alertToast(error)
            }
        }
    }

}

#Preview {
    TemporaryFileListView()
}
