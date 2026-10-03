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
        FileHomeGridContainer(
            files: files.map { FileState.ActiveFile.temporaryFile($0) },
            itemWidth: fileItemWidth,
            bottomPadding: 60,
            animatesChanges: false
        ) {
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
        } background: {
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
    
    
    @ViewBuilder
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
