//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import ComposableArchitecture

struct FileStore: ReducerProtocol {
    
    typealias State = SidebarBaseState<_State>
    
    struct _State: Equatable {
//        var currentFile: File?
//        var errors: [AppError]
//        var groups: [Group]
//        var currentGroup: Group?
        
        var fileList: IdentifiedArrayOf<FileRowStore.State> = []
        
//        var fileListState: IdentifiedArrayOf<FileRowStore.State> {
//            get {
//                .init(uniqueElements: fileList.map {
//                    FileRowStore.State(
//                        currentFile: self.currentFile,
//                        errors: self.errors,
//                        groups: self.groups,
//                        currentGroup: self.currentGroup,
//                        state: $0
//                    )
//                })
//            }
//            
//            set {
//                self.currentFile = newValue
//            }
//        }
    }
    
    enum Action: Equatable {
        case createNewFile
        
        case syncFiles(FetchedResults<File>)
        case fetchFiles
        case setFileList([File])
        case setCurrentFile(File?)
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
                case .fileRow(let id, let action):
                    switch action {
                        case .delegate(let action):
                            switch action {
                                case .didSetAsCurrentFile:
                                    if let file = state.fileList[id: id]?.file.fileEntity {
                                        return .send(.setCurrentFile(file))
                                    } else {
                                        return .none
                                    }
                                case .didRenameCurrentFile:
                                    return .none
                                case .didMoveCurrentFile:
                                    return .send(.fetchFiles)
                                case .willDuplicateFile(let file):
                                    let newFile = coreData.provider.duplicateFile(file: file)
                                    return .run { send in
                                        await send(.fetchFiles)
                                        await send(.setCurrentFile(newFile))
                                    }
                                case .didDeleteFile:
                                    return .send(.fetchFiles)
                                case .didRecoverFile:
                                    return .send(.fetchFiles)
                            }
                        default:
                            return .none
                    }
                    
                case .createNewFile:
                    guard let group = state.currentGroup else { return .none }
                    do {
                        let file = try coreData.provider.createFile(in: group)
                        return .run { send in
                            await send(.fetchFiles)
                            await send(.setCurrentFile(file))
                        }
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                    
                case .syncFiles(let files):
                    return .send(.setFileList(Array(files)))
                case .fetchFiles:
                    guard let group = state.currentGroup else { return .none }
                    let files: [File]
                    if group.groupType == .trash {
                         files = (try? coreData.provider.listTrashedFiles()) ?? []
                    } else {
                         files = (try? coreData.provider.listFiles(in: group)) ?? []
                    }
                    return .send(.setFileList(files))
                    
                case .setFileList(let files):
                    state.fileList = .init(uniqueElements: files.map {
                        FileRowStore.State(
                            currentFile: state.currentFile,
                            errors: state.errors,
                            groups: state.groups,
                            currentGroup: state.currentGroup,
                            state: .init(
                                file: .init(file: $0),
                                isSelected: state.currentFile?.id == $0.id
                            )
                        )
                    })
                    if !state.fileList.contains(where: {$0.id == state.currentFile?.id}) {
                        return .send(.setCurrentFile(state.fileList.first?.file.fileEntity))
                    }
                    return .none
                    
                case .setCurrentFile(let file):
                    state.currentFile = file
                    for fileRow in state.fileList {
                        state.fileList[id: fileRow.id]?.isSelected = fileRow.id == file?.id
                    }
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
    
//    @FetchRequest(sortDescriptors: [
//        SortDescriptor(\.updatedAt, order: .reverse),
//        SortDescriptor(\.createdAt, order: .reverse)
//    ])
//    var fileList: FetchedResults<File>
    
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
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .animation(.easeIn, value: viewStore.fileList)
            .watchImmediately(of: viewStore.currentGroup) { newValue in
                if newValue != nil {
                    self.store.send(.fetchFiles)
                }
            }
//            .watchImmediately(of: viewStore.group) { group in
//                guard let group = group else { return }
//                if group.groupType == .trash {
//                    fileList.nsPredicate = NSPredicate(format: "inTrash == YES")
//                } else {
//                    fileList.nsPredicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
//                }
//            }
//            .watchImmediately(of: fileList) { newValue in
//                print("fileList did changed")
//                viewStore.send(.syncFiles(newValue))
//            }
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
                initialState: .init(state: .init())
            ) {
                FileStore()
            }
        )
        .frame(width: 200)
    }
}
#endif
