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
        
        init(group: Group?) {
            self.group = group
        }
        
        var currentFile: File? {
            get { fileList.first(where: {$0.isSelected})?.file }
            set {
                for fileRow in fileList {
                    if fileRow.id == newValue?.id {
                        fileList[id: fileRow.id]?.isSelected = true
                    } else {
                        fileList[id: fileRow.id]?.isSelected = false
                    }
                }
            }
            
        }
    }
    
    enum Action: Equatable {
        case setGroup(Group)
        
        case createNewFile
        
        case fetchFiles
        case setFileList(IdentifiedArrayOf<FileRowStore.State>)
        case setCurrentFile(File)
        case fileRow(id: FileRowStore.State.ID, action: FileRowStore.Action)
        
        case delegate(Delegate)
        
        case setError(_ error: AppError)
        
        enum Delegate: Equatable {
            case didSetCurrentFile(File?)
        }
    }
    
    @Dependency(\.errorBus) var errorBus
    
    var body: some ReducerProtocol<State, Action> {
        @Dependency(\.coreData) var coreData
        
        Reduce { state, action in
            switch action {
                case .setGroup(let group):
                    state.group = group
                    return .none
                    
                case .fileRow(let id, let action):
                    switch action {
                        case .delegate(.didSetAsCurrentFile):
                            state.currentFile = state.fileList[id: id]?.file
                            return .none
                            
                        default:
                            return .none
                    }
                    
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
                    return .send(
                        .setFileList(.init(uniqueElements: files.map {
                            FileRowStore.State(file: $0, isSelected: false)
                        }))
                    )
                case .setFileList(let files):
                    state.fileList = files
                    if state.currentFile == nil,
                       let fileRow = state.fileList.first {
                        return .send(.setCurrentFile(fileRow.file))
                    }
                    return .none
                    
                case .setCurrentFile(let file):
                    state.currentFile = file
                    return .send(.delegate(.didSetCurrentFile(file)))
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
                    
                case .delegate:
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
            .watchImmediately(of: viewStore.group) { newValue in
                if newValue != nil {
                    self.store.send(.fetchFiles)
                }
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
