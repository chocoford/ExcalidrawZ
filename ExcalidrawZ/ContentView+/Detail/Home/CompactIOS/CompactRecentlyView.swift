//
//  CompactRecentlyView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/18/25.
//

import SwiftUI
import CoreData
import ChocofordUI

#if os(iOS)
@available(iOS 26.0, *)
struct CompactRecentlyView: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState

    @FetchRequest
    private var files: FetchedResults<File>

    init() {
        // Fetch all files not in trash
        self._files = FetchRequest<File>(
            sortDescriptors: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ],
            predicate: NSPredicate(format: "inTrash == false AND group != nil"),
            animation: .default
        )
    }
    
    @State private var editMode: EditMode = .inactive
    
    var columns: [GridItem] {
        switch layoutState.compactBrowserLayout {
            case .grid:
                [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ]
            case .list:
                [GridItem(.flexible(minimum: 0, maximum: 1000))]
        }
    }
    

    var body: some View {
        if #available(iOS 18.0, *) {
            content()
                .toolbarVisibility(editMode.isEditing ? .hidden : .visible, for: .tabBar)
        } else {
            content()
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(files) { file in
                        FileHomeItemView(
                            file: .file(file)
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("Recently")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode.isEditing == true {
                        
                    } else {
                        SettingsViewButton()
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    CompactContentMoreMenu()
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    
                }
            }
            .environment(\.editMode, $editMode)
        }
        .animation(.smooth, value: layoutState.compactBrowserLayout)
        // EditMode not working here ⬇️⬇️ 😅 Should use in NavigationStack
        // .environment(\.editMode, $editMode)
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        CompactRecentlyView()
    } else {
        // Fallback on earlier versions
    }
}
#endif
