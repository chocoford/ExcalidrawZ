//
//  CompactExcalidrawHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/18/25.
//

import SwiftUI
import SFSafeSymbols

#if os(iOS)
@available(iOS 26.0, *)
struct CompactExcalidrawHomeView: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    var disableInteration: Bool {
        fileState.currentActiveFile == nil
    }
    
    @StateObject private var toolState = ToolState()

    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            NavigationStack {
                ExcalidrawContainerWrapper(
                    activeFile: $fileState.currentActiveFile,
                    interactionEnabled: !disableInteration
                )
                .ignoresSafeArea()
                .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)
                .modifier(ExcalidrawContainerToolbarContentModifier())
#if os(iOS)
                .modifier(ApplePencilToolbarModifier())
#endif
                .modifier(LibraryTrailingSidebarModifier())
                .environmentObject(toolState)
            }
            
            TabView {
                Tab("Recently", systemImage: SFSymbol.clockFill.rawValue) {
                    CompactHomeView()
                }
                Tab("Collaboration", systemImage: SFSymbol.person3Fill.rawValue) {
                    CompactCollaborationHomeView()
                }
                Tab("Browse", systemImage: SFSymbol.folderFill.rawValue) {
                    CompactBrowseRootView()
                }
                Tab(role: .search) {
                    CompactSearchFilesView()
                }
            }
            .searchToolbarBehavior(.automatic)
            .opacity(fileHomeItemTransitionState.canShowItemContainerView ? 1 : 0)
            .allowsHitTesting(fileHomeItemTransitionState.canShowItemContainerView)
        }

    }
}

#Preview {
    if #available(iOS 26.0, *) {
        CompactExcalidrawHomeView()
    } else {
        // Fallback on earlier versions
    }
}
#endif
