//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import ChocofordUI

//struct ExcalidrawContainerStore: ReducerProtocol {
//    struct State: Equatable {
//        var excalidraw: ExcalidrawStore.State = .init()
//        
//        var isLoading: Bool = true
//        var colorScheme: ColorScheme = .light
//        
//        @BindingState var showRestoreAlert: Bool = false
//    }
//    
//    enum Action: Equatable, BindableAction {
//        case binding(BindingAction<State>)
//        case excalidraw(ExcalidrawStore.Action)
//        
//        case setColorScheme(ColorScheme)
//        case toggleRestoreAlert
//        
//        case delegate(Delegate)
//        
//        enum Delegate: Equatable {
//            case recoverFile(File)
//        }
//    }
//    
//    var body: some ReducerProtocol<State, Action> {
//        BindingReducer()
//        Scope(state: \.excalidraw, action: /Action.excalidraw) {
//            ExcalidrawStore()
//        }
//        
//        Reduce { state, action in
//            switch action {
//                case .excalidraw(.delegate(let action)):
//                    switch action {
//                        case .onFinishLoading:
//                            state.isLoading = false
//                            return .merge(
//                                .send(.excalidraw(.loadCurrentFile)),
//                                .send(.setColorScheme(state.colorScheme))
//                            )
//                            
//                        default:
//                            return .none
//                    }
//                    
//                case .excalidraw:
//                    return .none
//                    
//                case .setColorScheme(let colorScheme):
//                    state.colorScheme = colorScheme
//                    return .send(.excalidraw(.applyColorSceme(colorScheme)))
//                    
//                case .toggleRestoreAlert:
//                    state.showRestoreAlert.toggle()
//                    return .none
//                    
//                case .delegate, .binding:
//                    return .none
//            }
//        }
//    }
//}

struct ExcalidrawContainerView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var isLoading = true
    @State private var resotreAlertIsPresented = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                ExcalidrawWebView(isLoading: $isLoading)
                //                    .preferredColorScheme(appSettings.excalidrawAppearance.colorScheme)
                    .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading...")
                    }
                } else if fileState.currentFile?.inTrash == true {
                    recoverOverlayView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .transition(.opacity)
            .animation(.default, value: isLoading)
        }
//        .onChange(of: appSettings.excalidrawAppearance, initial: true) { newVal in
            //                if newVal == .auto {
            //                    viewStore.send(.setColorScheme(colorScheme))
            //                } else {
            //                    viewStore.send(.setColorScheme(newVal.colorScheme ?? colorScheme))
            //                }
//        }
        .onChange(of: colorScheme) { newVal in
            //                if appSettings.excalidrawAppearance == .auto {
            //                    viewStore.send(.setColorScheme(newVal))
            //                }
        }
    }
    
    @MainActor @ViewBuilder
    private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                resotreAlertIsPresented.toggle()
            }
            .alert("Recently deleted files can’t be edited.", isPresented: $resotreAlertIsPresented) {
                Button(role: .cancel) {
                    resotreAlertIsPresented.toggle()
                } label: {
                    Text("Cancel")
                }
                
                Button {
                    // Recover file
                    
                } label: {
                    Text("Recover")
                }
                
            } message: {
                Text("To edit this file, you’ll need to recover it.")
            }
    }
}


#if DEBUG
struct ExcalidrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcalidrawContainerView()
            .frame(width: 800, height: 600)
    }
}
#endif
