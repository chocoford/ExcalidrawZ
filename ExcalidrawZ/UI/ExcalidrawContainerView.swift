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
        var colorScheme: ColorScheme = .light
        
        @BindingState var showRestoreAlert: Bool = false
    }
    
    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case excalidraw(ExcalidrawStore.Action)
        
        case setColorScheme(ColorScheme)
        case toggleRestoreAlert
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case recoverFile(File)
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        BindingReducer()
        Scope(state: \.excalidraw, action: /Action.excalidraw) {
            ExcalidrawStore()
        }
        
        Reduce { state, action in
            switch action {
                case .excalidraw(.delegate(let action)):
                    switch action {
                        case .onFinishLoading:
                            state.isLoading = false
                            return .merge(
                                .send(.excalidraw(.loadCurrentFile)),
                                .send(.setColorScheme(state.colorScheme))
                            )
                            
                        default:
                            return .none
                    }
                    
                case .excalidraw:
                    return .none
                    
                case .setColorScheme(let colorScheme):
                    state.colorScheme = colorScheme
                    return .send(.excalidraw(.applyColorSceme(colorScheme)))
                    
                case .toggleRestoreAlert:
                    state.showRestoreAlert.toggle()
                    return .none
                    
                case .delegate, .binding:
                    return .none
            }
        }
    }
}

struct ExcalidrawContainerView: View {
    let store: StoreOf<ExcalidrawContainerStore>
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appSettings: AppSettingsStore

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
                    .preferredColorScheme(appSettings.excalidrawAppearance.colorScheme)
                    .opacity(viewStore.isLoading ? 0 : 1)
                    if viewStore.isLoading {
                        VStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Loading...")
                        }
                    } else if viewStore.excalidraw.currentFile?.inTrash == true {
                        recoverOverlayView
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .transition(.opacity)
                .animation(.default, value: viewStore.isLoading)
            }
            .watchImmediately(of: appSettings.excalidrawAppearance) { newVal in
                if newVal == .auto {
                    viewStore.send(.setColorScheme(colorScheme))
                } else {
                    viewStore.send(.setColorScheme(newVal.colorScheme ?? colorScheme))
                }
            }
            .onChange(of: colorScheme) { newVal in
                if appSettings.excalidrawAppearance == .auto {
                    viewStore.send(.setColorScheme(newVal))
                }
            }
        }
    }
}

extension ExcalidrawContainerView {
    @ViewBuilder private var recoverOverlayView: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Rectangle()
                .opacity(0)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewStore.send(.toggleRestoreAlert)
                }
                .onLongPressGesture(perform: {
                    viewStore.send(.toggleRestoreAlert)
                })
                .alert("Recently deleted files can’t be edited.", isPresented: viewStore.$showRestoreAlert) {
                    Button(role: .cancel) {
                        viewStore.send(.toggleRestoreAlert)
                    } label: {
                        Text("Cancel")
                    }
                    
                    Button {
                        if let file = viewStore.excalidraw.currentFile {
                            self.store.send(.delegate(.recoverFile(file)))
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
        ExcalidrawContainerView(
            store: .init(initialState: .init()) {
                ExcalidrawContainerStore()
            }
        )
        .frame(width: 800, height: 600)
    }
}
#endif
