//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials
import AlertToast
import Introspect
import ComposableArchitecture

struct AppViewStore: ReducerProtocol {
    struct State: Equatable {
        var errors: [AppError] = []
                
        @PresentationState var exportState: ExportImageStore.State?
        @PresentationState var shareState: ShareStore.State?
        var sidebar: SidebarStore.State = .init()
        var excalidrawContainer: ExcalidrawContainerStore.State = .init()
        var fileHistory: FileCheckpointListStore.State = .init()
    }
    
    enum Action: Equatable {
        case sidebar(SidebarStore.Action)
        
        case export(PresentationAction<ExportImageStore.Action>)
        case share(PresentationAction<ShareStore.Action>)
        
        case excalidrawContainer(ExcalidrawContainerStore.Action)
        case fileHistory(FileCheckpointListStore.Action)
                
        case importFile(_ url: URL)
        
        case shareButtonTapped
        
        case setError(_ error: AppError?)
        case dismissError
        
        case onAppear
        case empty
    }
    
    @Dependency(\.coreData) var coreData
    
    var body: some ReducerProtocol<State, Action> {
        @Dependency(\.errorBus) var errorBus
        
        Scope(state: \.sidebar, action: /Action.sidebar) {
            SidebarStore()
        }
        
        Scope(state: \.excalidrawContainer, action: /Action.excalidrawContainer) {
            ExcalidrawContainerStore()
        }
        
//        Scope(state: \.exportState, action: /Action.export) {
//            ExportStore()
//        }
        
        Scope(state: \.fileHistory, action: /Action.fileHistory) {
            FileCheckpointListStore()
        }

        Reduce { state, action in
            switch action {
                case .sidebar(.file(.delegate(let action))):
                    switch action {
                        case .didSetCurrentFile(let file):
                            return .run { send in
                                await send(.fileHistory(.fetchCurrentFileHistory(file)))
                                await send(.excalidrawContainer(.excalidraw(.setCurrentFile(file))))
                            }
                            
//                        default:
//                            return .none
                    }
                    
                    
                case .excalidrawContainer(.delegate(let action)):
                    switch action {
                        case .recoverFile(let file):
                            print("recover file", file)
                            return .none
                    }
                    
                case .excalidrawContainer(.excalidraw(.delegate(let action))):
                    switch action {
                        case .onBeginExport(let exportState):
                            if #available(macOS 13.0, *) {
                                if let presentID = state.shareState?.path.ids.last {
                                    return .send(.share(.presented(.path(
                                        .element(id: presentID, action: .exportImage(.setState(exportState))))
                                    )))
                                }
                            } else {
                                return .send(.export(.presented(.setState(exportState))))
                            }
                            return .none
                            
                        case .onExportDone:
                            if #available(macOS 13.0, *) {
                                if let presentID = state.shareState?.path.ids.last {
                                    return .send(.share(.presented(.path(
                                        .element(id: presentID, action: .exportImage(.setIsDone)))
                                    )))
                                }
                            } else {
                                return .send(.export(.presented(.setIsDone)))
                            }
                            return .none
                            
                        case .didUpdateFile:
                            return .run { [state] send in
                                await send(.fileHistory(.fetchCurrentFileHistory(state.sidebar.currentFile)))
                                await send(.sidebar(.file(.fetchFiles)))
                            }
                            
                        case .needCreateFile(let data):
                            return .concatenate(
                                .send(.sidebar(.file(.createNewFile))),
                                .send(.excalidrawContainer(.excalidraw(.updateCurrentFile(data))))
                            )
                            
                        default:
                            return .none
                    }
                    
                case .fileHistory(.checkpoint(_, action: .delegate(let action))):
                    switch action {
                        case .didDeleteCheckpoint(let ckpt):
                            coreData.viewContext.delete(ckpt)
                            coreData.provider.save()
                            return .send(.fileHistory(.fetchCurrentFileHistory(state.sidebar.currentFile)))
                        case .didRestoreCheckpoint(let ckpt):
                            if let data = ckpt.content {
                                return .send(.excalidrawContainer(.excalidraw(.restoreCheckpoint(data))))
                            } else {
                                return .none
                            }
                    }
                    
                case .export(.presented(.delegate(.onAppear))),
                        .share(.presented(.delegate(.willExportImage))):
                    return .send(
                        .excalidrawContainer(
                            .excalidraw(.exportPNGImage)
                        )
                    )
                    
                case .importFile(let url):
                    do {
                        guard url.pathExtension == "excalidraw" else { throw AppError.fileError(.invalidURL) }
                        let data = try Data(contentsOf: url, options: .uncached) // .uncached fixes the import bug occurs in x86 mac OS
                        guard let group = state.sidebar.currentGroup else { throw AppError.stateError(.currentGroupNil) }
                        let file = try coreData.provider.createFile(in: group)
                        file.name = String(url.lastPathComponent.split(separator: ".").first ?? "Untitled")
                        file.content = data
                        coreData.provider.save()
                        return .concatenate(
                            .send(.sidebar(.file(.fetchFiles))),
                            .send(.sidebar(.file(.setCurrentFile(file))))
                        )
                    } catch {
                        return .send(.setError(.init(error)))
                    }

                case .shareButtonTapped:
                    if #available(macOS 13.0, *) {
                        if let file = state.sidebar.currentFile {
                            state.shareState = .init(currentFile: file)
                        }
                    } else {
                        state.exportState = .init()
                    }
                    return .none
                    
                case .setError(let error?):
                    state.errors.append(error)
                    return .none
                    
                case .dismissError:
                    state.errors.removeFirst()
                    return .none
                    
                case .onAppear:
                    return .run { send in
                        for await error in errorBus.errorStream {
                            await send(.setError(.init(error)))
                        }
                    }
                    
                    
                case .sidebar, .export, .share, .excalidrawContainer, .fileHistory, .setError, .empty:
                    return .none
            }
        }
        .ifLet(\.$exportState, action: /Action.export) {
            ExportImageStore()
        }
        .ifLet(\.$shareState, action: /Action.share) {
            ShareStore()
        }
    }
}


struct ContentView: View {
    let store: StoreOf<AppViewStore>
    @State private var hideContent: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibilityCompatible = .automatic
    
    var body: some View {
        WithViewStore(self.store, observe: \.errors) { errors in
            content
                .toast(isPresenting: errors.binding(
                    get: { !$0.isEmpty },
                    send: { _ in .dismissError }
                ), alert: {
                    .init(displayMode: .hud, type: .error(.red), title: errors.first?.errorDescription)
                })
                .onAppear {
                    self.store.send(.onAppear)
                }
        }
    }
    
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            NavigationSplitViewCompatible(columnVisibility: $columnVisibility) {
                SidebarView(
                    store: self.store.scope(
                        state: \.sidebar,
                        action: AppViewStore.Action.sidebar
                    )
                )
//                .toolbar {
//                    ToolbarItem(placement: .primaryAction) {
//                        if #available(macOS 13.0, *) {
//                            Button {
//                                withAnimation {
//                                    if columnVisibility == .all {
//                                        columnVisibility = .detailOnly
//                                    } else {
//                                        columnVisibility = .all
//                                    }
//                                }
//                            } label: {
//                                Image(systemName: "sidebar.leading")
//                            }
//                        }
//                    }
//                }
            } detail: {
                HStack(spacing: 0) {
                    ExcalidrawContainerView(store: self.store.scope(
                        state: \.excalidrawContainer,
                        action: AppViewStore.Action.excalidrawContainer
                    ))
                    .sheet(
                        store: self.store.scope(state: \.$exportState,
                                                action: AppViewStore.Action.export)
                    ) {
                        ExportImageView(store: $0)
                    }
                    .sheet(
                        store: self.store.scope(state: \.$shareState,
                                                action: AppViewStore.Action.share)
                    ) {
                        if #available(macOS 13.0, *) {
                            ShareView(store: $0)
                        }
                    }
                }
                .toolbar(content: toolbarContent)
            }
            .navigationTitle("")
#if os(macOS)
            .navigationBarBackButtonHiddenCompatible()
#endif
        }
    }
}

extension ContentView {
    func createNewFile() {
        self.store.send(.sidebar(.file(.createNewFile)))
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
            WithViewStore(self.store, observe: \.sidebar.fileState) { file in
                Text(file.currentFile?.name ?? "Untitled")
                    .frame(width: 200)
            }
        }
        
        ToolbarItemGroup(placement: .navigation) {
            WithViewStore(self.store, observe: {$0}) { viewStore in
                // create
                Button {
                    createNewFile()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New draw")
                .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            WithViewStore(self.store, observe: {$0}) { viewStore in
                Spacer()
                Popover {
                    FileCheckpointListView(store: self.store.scope(
                        state: \.fileHistory,
                        action: AppViewStore.Action.fileHistory
                    ))
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)

                Button {
                    self.store.send(.shareButtonTapped)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
                .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)

            }

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
