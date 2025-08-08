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
        if #available(macOS 26.0, *) {
            oneColumnSidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 340)
        } else if #available(macOS 13.0, *) {
            oneColumnSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 340)
        } else {
            oneColumnSidebar()
                .frame(minWidth: 240)
        }
    }
    
    @MainActor @ViewBuilder
    private func oneColumnSidebar() -> some View {
        GroupListView()
            .border(.top, color: .separatorColor)
#if os(iOS)
        .background {
            List(selection: $fileState.currentActiveFile) {}
        }
#endif
        .environmentObject(localFolderState)
    }
}

#Preview {
    SidebarView()
}
