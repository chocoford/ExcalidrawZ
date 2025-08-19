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

    @StateObject private var dragState = SidebarDragState()

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
        GroupListView(sortField: fileState.sortField)
            .border(.top, color: .separatorColor)
#if os(iOS)
            .background {
                List(selection: $fileState.currentActiveFile) {}
            }
#endif
            .background {
                Color.clear.contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        dragState.currentDragItem = nil
                        dragState.currentDropFileRowTarget = nil
                    })
            }
            .environmentObject(dragState)
    }
}

class SidebarDragState: ObservableObject {
    
    enum DragItem: Hashable {
        case group(NSManagedObjectID)
        case file(NSManagedObjectID)
        case localFolder(NSManagedObjectID)
        case localFile(URL)
    }
    
    @Published var currentDragItem: DragItem?
    
    enum FileRowDropTarget: Equatable {
        case after(DragItem)
        case startOfGroup(DragItem)
    }
    @Published var currentDropFileRowTarget: FileRowDropTarget?
    
    enum GroupDropTarget: Equatable {
        case exact(DragItem)
        case below(DragItem)
    }
    
     @Published var currentDropGroupTarget: GroupDropTarget?
}

#Preview {
    SidebarView()
}
