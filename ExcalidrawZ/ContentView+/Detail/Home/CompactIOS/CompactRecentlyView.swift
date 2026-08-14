//
//  CompactRecentlyView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/18/25.
//

import SwiftUI
import ChocofordUI

#if os(iOS)
@available(iOS 26.0, *)
struct CompactRecentlyView: View {
    @EnvironmentObject private var layoutState: LayoutState
    
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
    
    @ViewBuilder
    private func content() -> some View {
        NavigationStack {
            RecentlyFilesProvider { activeFiles in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(activeFiles) { file in
                            FileHomeItemView(
                                file: file,
                                selectionSiblings: activeFiles,
                                subtitle: .location
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(.localizable(.compactRecentlyTitle))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode.isEditing == true {
                        
                    } else {
                        SettingsViewButton()
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    NewFileButton(usesFileHomeOpenTransition: true)
                    CompactContentMoreMenu()
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
