//
//  TemporaryFilesHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/21/25.
//

import SwiftUI

struct TemporaryFilesHomeView: View {
    @EnvironmentObject private var fileState: FileState

    init() {}
    
    let fileItemWidth: CGFloat = 240
    var files: [URL] { fileState.temporaryFiles }
    
    var body: some View {
        FileHomeContainer {
            // Header
            HStack {
                Text(.localizable(.sidebarGroupRowTitleTemporary))
                    .font(.title)
                
                Spacer()
                
                // Toolbar
                HStack {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        actionsMenu()
#if canImport(AppKit)
                            .buttonStyle(.accessoryBar)
#endif
                    } else {
                        actionsMenu()
                    }
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, 30)

            let activeFiles = files.map { FileState.ActiveFile.temporaryFile($0) }

            // Files
            LazyVGrid(
                columns: [
                    .init(.adaptive(minimum: fileItemWidth, maximum: fileItemWidth * 2 - 0.1), spacing: 20)
                ],
                spacing: 20
            ) {
                ForEach(activeFiles) { file in
                    FileHomeItemView(
                        file: file,
                        selectionSiblings: activeFiles
                    )
                }
                
            }
            .padding(30)
        }
        .contentBackground {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
#if canImport(AppKit)
                    if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                        return
                    }
#endif
                    fileState.resetSelections()
                }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func actionsMenu() -> some View {
        Menu {
            TemporaryGroupMenuItems()
        } label: {
            Image(systemSymbol: .ellipsisCircle)
        }
        .fixedSize()
        .menuIndicator(.hidden)
    }
}

#Preview {
    TemporaryFilesHomeView()
}
