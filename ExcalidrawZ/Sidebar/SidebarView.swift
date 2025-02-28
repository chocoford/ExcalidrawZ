//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI
import CoreData

import ChocofordUI

struct SidebarView: View {
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)]
    )
    var groups: FetchedResults<Group>
    
    @StateObject private var localFolderState = LocalFolderState()

    var body: some View {
        twoColumnSidebar()
    }
    
    
    @MainActor @ViewBuilder
    private func twoColumnSidebar() -> some View {
        HStack(spacing: 0) {
            if appPreference.sidebarMode == .all {
                GroupListView(groups: groups)
#if os(macOS)
                    .frame(minWidth: 150)
#endif
                Divider()
                    .ignoresSafeArea(edges: .bottom)
            }
            
            ZStack {
                if let currentGroup = fileState.currentGroup {
                    FileListView(
                        currentGroupID: currentGroup.id,
                        groupType: currentGroup.groupType
                    )
                } else if let currentLocalFolder = fileState.currentLocalFolder {
                    LocalFilesListView(folder: currentLocalFolder)
                } else {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        Text(.localizable(.sidebarFilesPlaceholder))
                            .foregroundStyle(.placeholder)
                    } else {
                        Text(.localizable(.sidebarFilesPlaceholder))
                            .foregroundStyle(.secondary)
                    }
                }
            }
#if os(macOS)
            .frame(minWidth: 200)
#endif
        }
        .border(.top, color: .separatorColor)
#if os(iOS)
        .background {
            List(selection: $fileState.currentFile) {}
        }
#endif
        .environmentObject(localFolderState)
    }
    
    @MainActor @ViewBuilder
    private func singleColumnSidebar() -> some View {
        List(selection: $fileState.currentFile) {
            
        }
    }
}

#Preview {
    SidebarView()
}
