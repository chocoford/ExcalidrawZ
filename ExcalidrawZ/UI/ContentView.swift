//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import Foundation
import ChocofordUI
import Introspect
import ComposableArchitecture

struct AppViewStore: ReducerProtocol {
    
    struct State: Equatable {
        var error: AppError?
        
        @PresentationState var exportState: ExportStore.State?
        var groupState: GroupStore.State = .init()
        var fileState: FileStore.State = .init(group: nil)
        var excalidrawContainer: ExcalidrawContainerStore.State = .init()
    }
    
    enum Action: Equatable {
        case group(GroupStore.Action)
        case file(FileStore.Action)
        case export(PresentationAction<ExportStore.Action>)
        case excalidrawContainer(ExcalidrawContainerStore.Action)
        
        case setFilesGroup(Group)
        
        case exportImageButtonTapped
        
        case setError(_ error: AppError?)
        
        case onAppear
        case empty
    }
    
    var body: some ReducerProtocol<State, Action> {
        @Dependency(\.errorBus) var errorBus
        
        Scope(state: \.groupState, action: /Action.group) {
            GroupStore()
        }
        
        Scope(state: \.fileState, action: /Action.file) {
            FileStore()
        }
        
        Scope(state: \.excalidrawContainer, action: /Action.excalidrawContainer) {
            ExcalidrawContainerStore()
        }

        Reduce { state, action in
            switch action {
                case .group(.delegate(let action)):
                    switch action {
                        case .didChooseGroup(let group):
                            return .send(.setFilesGroup(group))
                    }
                    
                case .excalidrawContainer(.delegate(let action)):
                    switch action {
                        case .recoverFile(let file):
                            print("recover file", file)
                            return .none
                            
                        case .onBeginExport(let exportState):
                            state.exportState = exportState
                            return .none
                            
                        case .onExportDone:
                            state.exportState?.done = true
                            return .none
                    }
                    
                case .exportImageButtonTapped:
                    return .send(.excalidrawContainer(.excalidraw(.exportPNGImage)))
                    
                case .setFilesGroup(let group):
                    state.fileState.group = group
                    return .none
                    
                case .onAppear:
                    return .run { send in
                        for await error in errorBus.errorStream {
                            await send(.setError(.init(error)))
                        }
                    }
                    
                case .group, .file, .export:
                    return .none
                default:
                    return .none
            }
        }
        .ifLet(\.$exportState, action: /Action.export) {
            ExportStore()
        }
        
    }
}

struct ContentView: View {
    let store: StoreOf<AppViewStore>
    @State private var hideContent: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibilityCompatible = .automatic
    
    var body: some View {
        WithViewStore(self.store, observe: \.error) { error in
            content
                .alert(
                    isPresented: error.binding(
                        get: { $0 != nil },
                        send: { val in
                            if !val { .setError(nil) }
                            else { .empty }
                        }
                    ),
                    error: error.state
                ) {}
        }
    }
    
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            NavigationSplitViewCompatible(columnVisibility: $columnVisibility) {
                GroupSidebarView(
                    store: self.store.scope(
                        state: \.groupState,
                        action: AppViewStore.Action.group
                    )
                )
                .frame(minWidth: 150)

            } detail: {
                HStack(spacing: 0) {
                    if columnVisibility != .detailOnly {
                        ResizableView(.horizontal, edge: .trailing, initialSize: 200, minSize: 200) {
                            FileListView(store: self.store.scope(
                                state: \.fileState,
                                action: AppViewStore.Action.file
                            ))
                        }
                        .border(.trailing, color: Color(nsColor: .separatorColor))
                    }
                    
                    ExcalidrawView(store: self.store.scope(
                        state: \.excalidrawContainer,
                        action: AppViewStore.Action.excalidrawContainer
                    ))
                    .toolbar(content: toolbarContent)
                    .sheet(store: self.store.scope(state: \.$exportState,
                                                   action: AppViewStore.Action.export)) {
                        ExportImageView(store: $0)
                    }
                }
            }
        }
    }
}

extension ContentView {
    func createNewFile() {
        self.store.send(.file(.createNewFile))
    }
}

// MARK: - Toolbar Content
extension ContentView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
#if os(iOS)
        toolbarContent_iOS()
#else
        toolbarContent_macOS()
#endif
    }
    
#if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        
    }
#else
    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
            WithViewStore(self.store, observe: \.fileState) { file in
                Text(file.currentFile?.name ?? "Untitled")
                    .frame(width: 200)
            }
        }
        
        ToolbarItemGroup(placement: .navigation) {
            // create
            Button {
                createNewFile()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New draw")
        }

        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            // create
            Button {
                
            } label: {
                Image(systemName: "camera.on.rectangle")
            }
            .help("Take a screenshot.")
        }
    }
#endif
}


#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            store: .init(initialState: .init()) {
                AppViewStore()
            }
        )
    }
}
#endif
