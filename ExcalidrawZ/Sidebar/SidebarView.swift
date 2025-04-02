//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI
import CoreData

import ChocofordUI

enum ExcalidrawFileSortField: String, Hashable {
    case updatedAt
    case name
    case rank
}


struct SidebarView: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.searchExcalidrawAction) private var searchExcalidraw
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    
    @StateObject private var localFolderState = LocalFolderState()

    var body: some View {
        if #available(macOS 13.0, *) {
            twoColumnSidebar()
                .navigationSplitViewColumnWidth(min: 374, ideal: 400, max: 500)
        } else {
            twoColumnSidebar()
        }
    }
    
    
    @MainActor @ViewBuilder
    private func twoColumnSidebar() -> some View {
        HStack(spacing: 0) {
            if appPreference.sidebarMode == .all {
                GroupListView()
                    .frame(minWidth: 174)
                Divider()
                    .ignoresSafeArea(edges: .bottom)
            }
            
            VStack(spacing: 0) {
                if let currentGroup = fileState.currentGroup {
                    FileListView(
                        currentGroupID: currentGroup.id,
                        groupType: currentGroup.groupType,
                        sortField: fileState.sortField
                    )
                } else if let currentLocalFolder = fileState.currentLocalFolder {
                    if #available(macOS 13.0, *) {
                        LocalFilesListView(
                            folder: currentLocalFolder,
                            sortField: fileState.sortField
                        )
                    } else {
                        LocalFilesListView(
                            folder: currentLocalFolder,
                            sortField: fileState.sortField
                        )
                        .id(currentLocalFolder)
                    }
                } else if fileState.isTemporaryGroupSelected {
                    TemporaryFileListView(sortField: fileState.sortField)
                } else if fileState.isInCollaborationSpace {
                    CollaborationFilesList(sortField: fileState.sortField)
                } else {
                    ZStack {
                        if #available(macOS 14.0, iOS 17.0, *) {
                            Text(.localizable(.sidebarFilesPlaceholder))
                                .foregroundStyle(.placeholder)
                        } else {
                            Text(.localizable(.sidebarFilesPlaceholder))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                Divider()
                if #available(macOS 14.0, *) {
                    contentToolbar()
#if canImport(AppKit)
                        .buttonStyle(.accessoryBar)
#endif
                } else {
                    contentToolbar()
                        .buttonStyle(.text(size: .small, square: true))
                }

            }
            .frame(minWidth:  200)
        }
        .border(.top, color: .separatorColor)
#if os(iOS)
        .background {
            if fileState.currentGroup != nil {
                List(selection: $fileState.currentFile) {}
            } else if fileState.currentLocalFolder != nil {
                List(selection: $fileState.currentLocalFile) {}
            } else if fileState.isTemporaryGroupSelected {
                List(selection: $fileState.currentTemporaryFile) {}
            } else if fileState.isInCollaborationSpace {
                List(selection: $fileState.currentCollaborationFile) {}
            }
        }
#endif
        .environmentObject(localFolderState)
    }
    
    @MainActor @ViewBuilder
    private func singleColumnSidebar() -> some View {
        List(selection: $fileState.currentFile) {
            
        }
    }
    
    
    @MainActor @ViewBuilder
    private func contentToolbar() -> some View {
        HStack {
            Button {
                searchExcalidraw()
            } label: {
                Label(.localizable(.searchButtonTitle), systemSymbol: .magnifyingglass)
                    .labelStyle(.iconOnly)
            }
            Spacer()
            if #available(macOS 13.0, *) {
                sortMenuButton()
            } else {
                sortMenuButton()
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.text(size: .small, square: true))
            }
        }
        .padding(4)
        .controlSize(.regular)
        .background(.ultraThickMaterial)
    }
    
    @MainActor @ViewBuilder
    private func sortMenuButton() -> some View {
        Menu {
            Picker(
                selection: Binding {
                    fileState.sortField
                } set: { val in
                    withAnimation {
                        fileState.sortField = val
                    }
                }
            ) {
                SwiftUI.Group {
                    Label(.localizable(.sortFileKeyName), systemSymbol: .textformat).tag(ExcalidrawFileSortField.name)
                    Label(.localizable(.sortFileKeyUpdatedAt), systemSymbol: .clock).tag(ExcalidrawFileSortField.updatedAt)
                }
                .labelStyle(.titleAndIcon)
            } label: { }
                .pickerStyle(.inline)
        } label: {
            if #available(macOS 13.0, *) {
                Label(.localizable(.sortFileButtonLabelTitle), systemSymbol: .arrowUpAndDownTextHorizontal)
                    .labelStyle(.iconOnly)
            } else {
                Label(.localizable(.sortFileButtonLabelTitle), systemSymbol: .arrowUpAndDownCircle)
                    .labelStyle(.iconOnly)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(fileState.isTemporaryGroupSelected || !fileState.hasAnyActiveGroup)
    }
}

#Preview {
    SidebarView()
}
