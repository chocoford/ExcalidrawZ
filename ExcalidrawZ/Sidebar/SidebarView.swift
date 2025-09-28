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
    @EnvironmentObject var dragState: ItemDragState

    var body: some View {
        if #available(macOS 26.0, *) {
            oneColumnSidebar()
                .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 340)
        } else if #available(macOS 13.0, *) {
            oneColumnSidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 240, max: 340)
        } else {
            oneColumnSidebar()
                .frame(width: 210)
        }
    }
    
    @MainActor @ViewBuilder
    private func oneColumnSidebar() -> some View {
        GroupListView(sortField: fileState.sortField)
            .border(.top, color: .separatorColor)
#if os(iOS)
            .background {
                List(selection: $fileState.currentActiveFile) {}
            }
#endif
            // Not working
            .background {
                Color.clear.contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        dragState.reset()
                        fileState.resetSelections()
                    })
            }
    }
}

#Preview {
    SidebarView()
}
