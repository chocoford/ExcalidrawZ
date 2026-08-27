//
//  CompactExcalidrawHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/18/25.
//

import SwiftUI
import SFSafeSymbols
import ChocofordUI

#if os(iOS)
@available(iOS 26.0, *)
struct CompactExcalidrawHomeView: View {
    private enum HomeTab: Hashable {
        case recently
        case collaboration
        case browse
        case search
    }

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    var disableInteration: Bool {
        fileState.currentActiveFile == nil
    }

    @State private var searchText = ""
    @State private var navigationPath: [EditorRoute] = []
    @State private var selectedTab: HomeTab = .recently

    
    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                ZStack {
                    ExcalidrawEditor(
                        activeFile: fileState.activeFileBinding,
                        interactionEnabled: !disableInteration
                    )
                    .ignoresSafeArea()
                    .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)
                    .modifier(InspectorPresentationModifier())
                }
                .navigationDestination(for: EditorRoute.self) { route in
                    switch route {
                    case .aiChat:
                        AIChatView()
                            .background(.background)
                            .navigationTitle(String(localizable: .aiChatTitle))
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .watch(value: layoutState.editorRouteRequest) { _, route in
                    handleRouteRequest(route)
                }
                .watch(value: navigationPath) { _, path in
                    layoutState.isCompactAIChatFullChatPresented = path.contains(.aiChat)
                }
                .watch(value: fileState.currentActiveFile?.id) { _, activeFileID in
                    guard activeFileID == nil else { return }
                    navigationPath.removeAll()
                }
            }
            
            TabView(selection: $selectedTab) {
                Tab(
                    .localizable(.compactRecentlyTitle),
                    systemImage: SFSymbol.clockFill.rawValue,
                    value: HomeTab.recently
                ) {
                    CompactRecentlyView()
                        .environment(
                            \.fileHomeItemTransitionSourceEnabled,
                            selectedTab == .recently
                        )
                        .onAppear {
                            fileState.currentActiveGroup = nil
                        }
                }
                Tab(
                    .localizable(.collaborationHomeTitle),
                    systemImage: SFSymbol.person3Fill.rawValue,
                    value: HomeTab.collaboration
                ) {
                    CompactCollaborationHomeView()
                        .environment(
                            \.fileHomeItemTransitionSourceEnabled,
                            selectedTab == .collaboration
                        )
                        .onAppear {
                            fileState.currentActiveGroup = .collaboration
                        }
                }
                Tab(
                    .localizable(.compactBrowserTitle),
                    systemImage: SFSymbol.folderFill.rawValue,
                    value: HomeTab.browse
                ) {
                    CompactBrowseRootView()
                        .environment(
                            \.fileHomeItemTransitionSourceEnabled,
                            selectedTab == .browse
                        )
                        .onAppear {
                            fileState.currentActiveGroup = nil
                        }
                }
                Tab(value: HomeTab.search, role: .search) {
                    CompactSearchFilesView()
                        .environment(
                            \.fileHomeItemTransitionSourceEnabled,
                            selectedTab == .search
                        )
                        .onAppear {
                            fileState.currentActiveGroup = nil
                        }
                }
            }
            .searchToolbarBehavior(.automatic)
            .opacity(fileHomeItemTransitionState.canShowItemContainerView ? 1 : 0)
            .allowsHitTesting(fileHomeItemTransitionState.canShowItemContainerView)
            .modifier(CompactExcalidrawHomeTabBarAccessoryViewModifier())
        }

    }

    private func handleRouteRequest(_ route: EditorRoute?) {
        guard let route else { return }
        pushRoute(route)
        layoutState.editorRouteRequest = nil
    }

    private func pushRoute(_ route: EditorRoute) {
        guard navigationPath.last != route else { return }
        navigationPath.append(route)
    }
}


struct CompactExcalidrawHomeTabBarAccessoryViewModifier: ViewModifier {
    @ObservedObject private var syncState = FileStatusService.shared.syncState

    @State private var isSyncStatePopoverPresented = false

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: isSyncStatePopoverPresented) {
                    SyncStatusContentView()
                }
                .onChange(of: syncState.shouldShowGlobalSyncStatus, initial: true, throttle: 0.2, latest: true) { _, newVal in
                    withAnimation(.smooth) {
                        isSyncStatePopoverPresented = newVal
                    }
                }
        } else {
            content
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
