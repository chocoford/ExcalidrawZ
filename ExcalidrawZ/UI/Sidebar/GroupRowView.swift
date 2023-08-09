//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture

struct GroupInfo: Equatable {
    private(set) var groupEntity: Group
    
    // group info
    private(set) var id: UUID
    private(set) var name: String
    private(set) var type: Group.GroupType
    private(set) var createdAt: Date
    private(set) var icon: String?
//    private(set) var files: [File]
    
    init(_ groupEntity: Group) {
        self.groupEntity = groupEntity
        self.id = groupEntity.id ?? UUID()
        self.name = groupEntity.name ?? "Untitled"
        self.type = groupEntity.groupType
        self.createdAt = groupEntity.createdAt ?? .distantPast
        self.icon = groupEntity.icon
        
//        self.files = groupEntity.files?.allObjects
    }
    
    public mutating func rename(_ newName: String) {
        self.name = newName
        self.groupEntity.name = newName
    }
    
    public func delete() {
//        self.groupEntity
    }
}


struct GroupRowStore: ReducerProtocol {
    struct State: Equatable, Identifiable {
        var id: UUID { group.id }
        var group: GroupInfo
        var isSelected: Bool
        
        @BindingState var isRenameSheetPresent: Bool = false
        
        var deleteConfirmation: ConfirmationDialogState<Action>?
        var emptyTrashConfirmation: ConfirmationDialogState<Action>?
        
        init(group: Group, isSelected: Bool) {
            self.group = .init(group)
            self.isSelected = isSelected
        }
    }
    
    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        
        case setAsCurrentGroup
        case moveFileToGroup(fileID: File.ID)
        case clearFiles
        
        case renameButtonTapped
        case renameCurrentGroup(String)
        
        case deleteButtonTapped
        case deleteConfirm
        case deleteCancel
        
        case emptyTrashButtonTapped
        case emptyTrashConfirm
        case emptyTrashCancel
        
        case setError(AppError)
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case didSetAsCurrentGroup
            case didDeleteGroupOrEmptyTrash
        }
    }
    
    @Dependency(\.errorBus) var errorBus
    @Dependency(\.coreData) var coreData
    
    var body: some ReducerProtocol<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .binding:
                    return .none
                case .setAsCurrentGroup:
                    return .send(.delegate(.didSetAsCurrentGroup))
                case .moveFileToGroup(let fileID):
                    return .none
                case .clearFiles:
                    return .none
                case .renameButtonTapped:
                    state.isRenameSheetPresent = true
                    return .none
                case .renameCurrentGroup(let newName):
                    state.group.rename(newName)
                    coreData.provider.save()
                    return.none
                case .deleteButtonTapped:
                    state.deleteConfirmation = ConfirmationDialogState {
                        TextState("Delete Confirmation")
                    } actions: {
                        ButtonState(role: .cancel) {
                            TextState("Cancel")
                        }
                        ButtonState(role: .destructive, action: .deleteConfirm) {
                            TextState("Delete")
                        }
                    } message: { [state] in
                        TextState("Are you sure you want to delete the folder \(state.group.name)?")
                    }
                    return .none
                    
                case .deleteConfirm:
                    do {
                        guard let defaultGroup = try coreData.provider.getDefaultGroup() else { throw AppError.fileError(.notFound) }
                        let files = try coreData.provider.listFiles(in: state.group.groupEntity)
                        for file in files {
                            file.inTrash = true
                            file.deletedAt = .now
                            file.group = defaultGroup
                        }
                        coreData.viewContext.delete(state.group.groupEntity)
                        coreData.provider.save()
                        return .send(.delegate(.didDeleteGroupOrEmptyTrash))
                    } catch {
                        return .none
                    }
                    
                case .deleteCancel:
                    state.deleteConfirmation = nil
                    return .none
                    
                case .emptyTrashButtonTapped:
                    state.emptyTrashConfirmation = ConfirmationDialogState {
                        TextState("Empty trash")
                    } actions: {
                        ButtonState(role: .cancel) {
                            TextState("Cancel")
                        }
                        ButtonState(role: .destructive, action: .emptyTrashConfirm) {
                            TextState("Delete")
                        }
                    } message: {
                        TextState("Are you sure you want to empty trash?")
                    }
                    return .none
                    
                case .emptyTrashConfirm:
                    do {
                        let files = try coreData.provider.listTrashedFiles()
                        files.forEach { coreData.viewContext.delete($0) }
                        coreData.provider.save()
                        return .send(.delegate(.didDeleteGroupOrEmptyTrash))
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                    
                case .emptyTrashCancel:
                    state.emptyTrashConfirmation = nil
                    return .none
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
                    
                case .delegate:
                    return .none

            }
        }
    }
}

struct GroupRowView: View {
    let store: StoreOf<GroupRowStore>
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            if viewStore.group.type != .trash {
                if #available(macOS 13.0, *) {
                    content
                        .dropDestination(for: FileLocalizable.self) { fileInfos, location in
                            guard let file = fileInfos.first else { return false }
                            viewStore.send(.moveFileToGroup(fileID: file.fileID))
                            return true
                        }
                } else {
                    content
                }
            } else {
                content
            }
        }
    }
    
    @MainActor
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Button {
                viewStore.send(.setAsCurrentGroup)
            } label: {
                HStack {
                    Label { Text(viewStore.group.name).lineLimit(1) } icon: { groupIcon }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ListButtonStyle(selected: viewStore.isSelected))
            .contextMenu { contextMenuView }
            .confirmationDialog(
                self.store.scope(state: \.deleteConfirmation, action: { $0 }),
                dismiss: .deleteCancel
            )
            .confirmationDialog(
                self.store.scope(state: \.emptyTrashConfirmation, action: { $0 }),
                dismiss: .emptyTrashCancel
            )
            .sheet(isPresented: viewStore.$isRenameSheetPresent) {
                RenameSheetView(text: viewStore.group.name) { newName in
                    viewStore.send(.renameCurrentGroup(newName))
                }
            }
        }
    }
    
}

extension GroupRowView {
    @ViewBuilder private var groupIcon: some View {
        WithViewStore(self.store, observe: \.group) { group in
            switch group.type {
                case .`default`:
                    Image(systemName: "folder")
                case .trash:
                    Image(systemName: "trash")
                case .normal:
                    Image(systemName: group.icon ?? "folder")
            }
        }
    }
}


// MARK: - Context Menu
extension GroupRowView {
    @ViewBuilder private var contextMenuView: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            if viewStore.group.type == .normal {
                Button {
                    viewStore.send(.renameButtonTapped)
                } label: {
                    Label("rename", systemImage: "pencil.line")
                }
                
                Button(role: .destructive) {
                    viewStore.send(.deleteButtonTapped)
                } label: {
                    Label("delete", systemImage: "trash")
                }
            } else if viewStore.group.type == .trash {
                Button(role: .destructive) {
                    viewStore.send(.emptyTrashButtonTapped)
                } label: {
                    Label("empty", systemImage: "trash")
                }
            } else if viewStore.group.type == .default {
                Button {
                    viewStore.send(.renameButtonTapped)
                } label: {
                    Label("rename", systemImage: "pencil.line")
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
}


// MARK: - Alert
fileprivate extension View {
    @ViewBuilder func deleteAlert(isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        self
            .alert("Are you sure you want to delete the folder)?", isPresented: isPresented, actions: {
                Button(role: .cancel) {
                    isPresented.wrappedValue.toggle()
                } label: {
                    Label("Cancel", systemImage: "trash")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }) {
                Text("All files will be deleted.")
            }
    }
    
    @ViewBuilder func emptyAlert(isPresented: Binding<Bool>, onEmpty: @escaping () -> Void) -> some View {
        self
            .alert("Are you sure you want to empty the trash?", isPresented: isPresented, actions: {
                Button(role: .cancel) {
                    isPresented.wrappedValue.toggle()
                } label: {
                    Label("Cancel", systemImage: "trash")
                }
                Button(role: .destructive) {
                    onEmpty()
                } label: {
                    Label("Empty", systemImage: "trash")
                }
            }) {
                Text("All files will be permanently deleted.")
            }
    }
}




#if DEBUG
struct GroupRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            GroupRowView(
                store: .init(initialState: .init(group: .preview, isSelected: false)) {
                    GroupRowStore()
                }
            )
            
            GroupRowView(
                store: .init(initialState: .init(group: .preview, isSelected: true)) {
                    GroupRowStore()
                }
            )
        }
        .padding()
    }
}
#endif
