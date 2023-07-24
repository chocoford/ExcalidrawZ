//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import ComposableArchitecture

struct FileStore: ReducerProtocol {
    struct State: Equatable {
        var group: Group?
        var fileList: IdentifiedArrayOf<FileRowStore.State> = []
        var currentFile: File?
        
        init(group: Group?) {
            self.group = group
        }
    }
    
    enum Action: Equatable {
        case createNewFile
        
        case fetchFiles
        case setFileList(IdentifiedArrayOf<FileRowStore.State>)
        case setCurrentFile(File)
        case fileRow(id: FileRowStore.State.ID, action: FileRowStore.Action)
        
        case setError(_ error: AppError)
    }
    
    @Dependency(\.errorBus) var errorBus
    
    var body: some ReducerProtocol<State, Action> {
        @Dependency(\.coreData) var coreData
        
        Reduce { state, action in
            switch action {
                case .createNewFile:
                    guard let group = state.group else { return .none }
                    do {
                        let file = try coreData.provider.createFile(in: group)
                        return .send(.setCurrentFile(file))
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                case .fetchFiles:
                    guard let group = state.group else { return .none }
                    let files = (try? coreData.provider.listFiles(in: group)) ?? []
                    return .send(.setFileList(.init(uniqueElements: files.map { FileRowStore.State(file: $0, isSelected: false) })))
                case .setFileList(let files):
                    state.fileList = files
                    return .none
                case .setCurrentFile(let file):
                    state.currentFile = file
                    return .none
                    
                case .fileRow:
                    return .none
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
            }
        }
        .forEach(\.fileList, action: /Action.fileRow) {
            FileRowStore()
        }
    }
}


struct FileListView: View {
    let store: StoreOf<FileStore>
    
    init(store: StoreOf<FileStore>) {
        self.store = store
    }
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            ScrollView {
                VStack(alignment: .leading) {
                    ForEachStore(
                        self.store.scope(state: \.fileList,
                                         action: FileStore.Action.fileRow)
                    ) { store in
                        FileRowView(store: store)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .transition(.opacity)
            }
            .animation(.easeIn, value: viewStore.fileList)
            .onAppear {
                viewStore.send(.fetchFiles)
            }
        }
    }
}

extension FileListView {
    @ToolbarContentBuilder private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Button {
                
            } label: {
                Image(systemName: "trash")
            }
        }
    }
}


#if DEBUG
struct FileListView_Previews: PreviewProvider {
    static var previews: some View {
        FileListView(
            store: .init(
                initialState: .init(
                    group: Group.preview
                )
            ) {
                FileStore()
            }
        )
        .frame(width: 200)
    }
}
#endif
