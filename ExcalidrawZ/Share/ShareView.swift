//
//  ShareView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/7.
//

import SwiftUI
import ChocofordUI

//struct ShareStore: ReducerProtocol {
//    struct State: Equatable {
//        var currentFile: File
//        var path = StackState<Path.State>()
//    }
//    
//    enum Action: Equatable {
//        case gotoExportImageView
//        case gotoExportFileView
//        case gotoArchive
//        
//        case path(StackAction<Path.State, Path.Action>)
//        case cancelButtonTapped
//        
//        case delegate(Delegate)
//        
//        enum Delegate: Equatable {
//            case willExportImage
//        }
//    }
//    
//    @Dependency(\.dismiss) var dismiss
//    
//    var body: some ReducerProtocol<State, Action> {
//        Reduce { state, action in
//            switch action {
//                case .gotoExportImageView:
//                    state.path.append(.exportImage())
//                    return .none
//                    
//                case .gotoExportFileView:
//                    state.path.append(.exportFile(.init(file: state.currentFile)))
//                    return .none
//                    
//                case .gotoArchive:
//                    do {
//                        try archiveAllFiles()
//                        return .run { send in
//                            await dismiss()
//                        }
//                    } catch {
//                        return .none
//                    }
//                    
//                    
//                case .path(let action):
//                    switch action {
//                        case .element(_, action: let action):
//                            switch action {
//                                case .exportImage(let action):
//                                    switch action {
//                                        case .delegate(.onAppear):
//                                            return .send(.delegate(.willExportImage))
//                                            
//                                        default:
//                                            return .none
//                                    }
//                                    
//                                case .exportFile:
//                                    return .none
//                            }
//                            
//                        default:
//                            return .none
//                    }
//                    
//                case .cancelButtonTapped:
//                    return .run { send in
//                        await dismiss()
//                    }
//
//                case .delegate:
//                    return .none
//            }
//        }
//        .forEach(\.path, action: /Action.path) {
//            Path()
//        }
//    }
//    
//    struct Path: ReducerProtocol {
//        enum State: Equatable, Hashable {
//            case exportImage(ExportImageStore.State = .init())
//            case exportFile(ExportFileStore.State)
//        }
//        
//        enum Action: Equatable {
//            case exportImage(ExportImageStore.Action)
//            case exportFile(ExportFileStore.Action)
//        }
//        
//        var body: some ReducerProtocol<State, Action> {
//            Scope(state: /State.exportImage, action: /Action.exportImage) {
//                ExportImageStore()
//            }
//            
//            Scope(state: /State.exportFile, action: /Action.exportFile) {
//                ExportFileStore()
//            }
//        }
//    }
//}

@available(macOS 13.0, *)
struct ShareView: View {
    var body: some View {
        NavigationStack {
            List {
//                squareButton(.gotoExportImageView) {
//                    Label("Export image", systemImage: "photo")
//                        .font(.title3)
//                }
//                squareButton(.gotoExportFileView) {
//                    Label("Export current file", systemImage: "doc")
//                        .font(.title3)
//                }
//                squareButton(.gotoArchive) {
//                    Label("Archive files", systemImage: "archivebox")
//                        .font(.title3)
//                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
//                        self.store.send(.cancelButtonTapped)
                    } label: {
                        Text("Dismiss")
                    }
                }
            }
//            .opacity(viewStore.path.count > 0 ? 0 : 1)
            .navigationTitle("Share")
        }
//        .navigationDestination(for: <#T##Hashable.Type#>, destination: <#T##(Hashable) -> View#>)
//        destination: { state in
//            switch state {
//                case .exportImage:
//                    CaseLet(
//                        /ShareStore.Path.State.exportImage,
//                         action: ShareStore.Path.Action.exportImage,
//                         then: ExportImageView.init
//                    )
//                case .exportFile:
//                    CaseLet(
//                        /ShareStore.Path.State.exportFile,
//                         action: ShareStore.Path.Action.exportFile,
//                         then: ExportFileView.init
//                    )
//            }
//        }
        .frame(width: 400, height: 300)
    }
    
//    @ViewBuilder
//    private func squareButton<Label: View>(
//        _ action: ShareStore.Action,
//        @ViewBuilder label: () -> Label
//    ) -> some View {
//        Button {
//            self.store.send(action)
//        } label: {
//            HStack {
//                label()
//                Spacer()
//            }
//            .frame(width: nil, height: 50)
//        }
//        .buttonStyle(ListButtonStyle())
//    }
}

#if DEBUG
//#Preview {
//    if #available(macOS 13.0, *) {
//        return ShareView(
//            store: .init(initialState: .init(currentFile: .preview)) {
//                ShareStore()
//            })
//    } else {
//        // Fallback on earlier versions
//        return EmptyView()
//    }
//}
#endif
