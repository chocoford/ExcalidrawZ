//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture

struct FileCheckpointRowStore: ReducerProtocol {
    struct State: Equatable, Identifiable {
        var checkpoint: FileCheckpoint
        
        var id: UUID? { checkpoint.id }
    }
    
    enum Action: Equatable {
        case restoreCheckpoint
        case deleteCheckpoint
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case didRestoreCheckpoint(FileCheckpoint)
            case didDeleteCheckpoint(FileCheckpoint)
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .restoreCheckpoint:
                    return .send(.delegate(.didRestoreCheckpoint(state.checkpoint)))
                    
                case .deleteCheckpoint:
                    return .send(.delegate(.didDeleteCheckpoint(state.checkpoint)))
                    
                case .delegate:
                    return .none
            }
        }
    }
}
 
struct FileCheckpointRowView: View {
    let store: StoreOf<FileCheckpointRowStore>
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Popover(arrowEdge: .trailing) {
                VStack(spacing: 12) {
                    ExcalidrawImageView(data: viewStore.checkpoint.content)
                        .frame(width: 400, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    VStack(spacing: 8) {
                        (
                            Text(viewStore.checkpoint.filename ?? "Untitled")
                        )
                        .font(.title)
                        
                        Text(viewStore.checkpoint.updatedAt?.formatted() ?? "")
                    }
                    
                    HStack {
                        Button {
                            viewStore.send(.restoreCheckpoint)
                        } label: {
                            Text("Restore")
                        }
                        
                        Button {
                            viewStore.send(.deleteCheckpoint)
                        } label: {
                            Text("Delete")
                        }
                    }
                }
                .padding(40)
                
            } label: {
                HStack {
                    //                VStack(alignment: .leading) {
                    Text(viewStore.checkpoint.filename ?? "")
                        .font(.headline)
                    Spacer()
                    Text(viewStore.checkpoint.updatedAt?.formatted() ?? "")
                    //                HStack {
                    //                    Spacer()
                    //                    Text(checkpoint.content?.getSize() ?? "")
                    //                        .font(.footnote)
                    //                }
                    //            }
                }
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .buttonStyle(ListButtonStyle())
        }
    }
}


#if DEBUG
#Preview {
    FileCheckpointRowView(
        store: .init(initialState: .init(checkpoint: .preview)) {
            FileCheckpointRowStore()
        }
    )
}
#endif
