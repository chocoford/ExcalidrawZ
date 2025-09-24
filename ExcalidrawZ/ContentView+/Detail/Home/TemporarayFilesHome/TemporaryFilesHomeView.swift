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
                            .buttonStyle(.accessoryBar)
                    } else {
                        actionsMenu()
                    }
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, 30)
            
            // Files
            LazyVGrid(
                columns: [
                    .init(.adaptive(minimum: fileItemWidth, maximum: fileItemWidth * 2 - 0.1), spacing: 20)
                ],
                spacing: 20
            ) {
                ForEach(files, id: \.self) { file in
                    FileHomeItemView(
                        file: .temporaryFile(file)
                    )
                }
                
            }
            .padding(30)
        }
        .contentBackground {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                        return
                    }
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
