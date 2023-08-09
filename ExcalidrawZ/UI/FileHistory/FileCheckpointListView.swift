//
//  FileCheckpointListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials
import ComposableArchitecture

struct FileCheckpointListStore: ReducerProtocol {
    struct State: Equatable {
        var checkpoints: IdentifiedArrayOf<FileCheckpointRowStore.State> = []
    }
    
    enum Action: Equatable {
        case checkpoint(id: FileCheckpointRowStore.State.ID, action: FileCheckpointRowStore.Action)
        case fetchCurrentFileHistory(File?)
        
        case setError(AppError)
    }
    
    @Dependency(\.coreData) var coreData
    @Dependency(\.errorBus) var errorBus
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .checkpoint:
                    return .none
                    
                case .fetchCurrentFileHistory(let file):
                    do {
                        if let file = file {
                            let checkpoints = try coreData.provider.fetchFileCheckpoints(of: file)
                            state.checkpoints = .init(uniqueElements: checkpoints.map{FileCheckpointRowStore.State(checkpoint: $0)})
                        }
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                    return .none
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
            }
        }
        .forEach(\.checkpoints, action: /Action.checkpoint) {
            FileCheckpointRowStore()
        }
    }
}

struct FileCheckpointListView: View {
    let store: StoreOf<FileCheckpointListStore>
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            List {
                ForEachStore(self.store.scope(
                    state: \.checkpoints,
                    action: FileCheckpointListStore.Action.checkpoint
                )) { checkpoint in
                    FileCheckpointRowView(store: checkpoint)
                }
            }
            .animation(.default, value: viewStore.checkpoints)
            .listStyle(.plain)
        }
    }
}


#if DEBUG
#Preview {
    FileCheckpointListView(store: .init(initialState: .init()) {
        FileCheckpointListStore()
    })
}
#endif
