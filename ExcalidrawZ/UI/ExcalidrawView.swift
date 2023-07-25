//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture

struct ExcalidrawContainerStore: ReducerProtocol {
    struct State: Equatable {
        var excalidraw: ExcalidrawStore.State = .init()
        
        var isLoading: Bool = true
    }
    
    enum Action: Equatable {
        case excalidraw(ExcalidrawStore.Action)
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case recoverFile(File)
            case onBeginExport(ExportStore.State)
            case onExportDone
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .excalidraw(.delegate(let action)):
                    switch action {
                        case .onFinishLoading:
                            state.isLoading = false
                            return .none
                        case .onBeginExport(let exportState):
                            return .send(.delegate(.onBeginExport(exportState)))
                        case .onExportDone:
                            return .send(.delegate(.onExportDone))
                    }
                    
                case .excalidraw:
                    return .none
                case .delegate:
                    return .none
            }
        }
    }
}

struct ExcalidrawView: View {
    let store: StoreOf<ExcalidrawContainerStore>
    @EnvironmentObject var appSettings: AppSettingsStore

    @State private var showRestoreAlert = false

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            GeometryReader { geometry in
                ZStack(alignment: .center) {
                    ExcalidrawWebView(
                        store: self.store.scope(
                            state: \.excalidraw,
                            action: ExcalidrawContainerStore.Action.excalidraw
                        )
                    )
                    .preferredColorScheme(appSettings.appearance.colorScheme)
                    .opacity(viewStore.isLoading ? 0 : 1)
                    if viewStore.isLoading {
                        VStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Loading...")
                        }
                        //                } else if currentFile.wrappedValue?.inTrash == true {
                        //                    recoverOverlayView
                        //                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .transition(.opacity)
                .animation(.default, value: viewStore.isLoading)
            }
        }
    }
}

extension ExcalidrawView {
    @ViewBuilder private var recoverOverlayView: some View {
        WithViewStore(store, observe: {$0.excalidraw.currentFile}) { currentFile in
            Rectangle()
                .opacity(0)
                .contentShape(Rectangle())
                .onTapGesture {
                    showRestoreAlert.toggle()
                }
                .onLongPressGesture(perform: {
                    showRestoreAlert.toggle()
                })
                .alert("Recently deleted files can’t be edited.", isPresented: $showRestoreAlert) {
                    Button(role: .cancel) {
                        showRestoreAlert.toggle()
                    } label: {
                        Text("Cancel")
                    }
                    
                    Button {
                        if let file = currentFile.state {
                            store.send(.delegate(.recoverFile(file)))
                        }
                    } label: {
                        Text("Recover")
                    }
                    
                } message: {
                    Text("To edit this file, you’ll need to recover it.")
                }
        }
    }
}

#if DEBUG
struct ExcalidrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcalidrawView(
            store: .init(initialState: .init()) {
                ExcalidrawContainerStore()
            }
        )
        .frame(width: 800, height: 600)
    }
}
#endif
