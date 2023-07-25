//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture

struct GroupRowStore: ReducerProtocol {
    struct State: Equatable, Identifiable {
        var id: UUID { group.id ?? UUID() }
        var group: Group
        var isSelected: Bool
        
        init(group: Group, isSelected: Bool) {
            self.group = group
            self.isSelected = isSelected
        }
    }
    
    enum Action: Equatable {
        case setAsCurrentGroup
        case moveFileToGroup(fileID: File.ID)
        case clearFiles
        case delete
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case didSetAsCurrentGroup
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setAsCurrentGroup:
                    return .send(.delegate(.didSetAsCurrentGroup))
                case .moveFileToGroup(let fileID):
                    return .none
                case .clearFiles:
                    return .none
                case .delete:
                    return .none
                    
                case .delegate:
                    return .none
            }
        }
    }
}

struct GroupRowView: View {
    let store: StoreOf<GroupRowStore>
    
    @State private var alertDeletion = false
    @State private var alertEmpty = false
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            if viewStore.group.groupType != .trash {
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
    
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Button {
                viewStore.send(.setAsCurrentGroup)
            } label: {
                HStack {
                    Label { Text(viewStore.group.name ?? "Untitled").lineLimit(1) } icon: { groupIcon }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ListButtonStyle(selected: viewStore.isSelected))
            .contextMenu { contextMenuView }
            .deleteAlert(isPresented: $alertDeletion, onDelete: deleteGroup)
            .emptyAlert(isPresented: $alertEmpty, onEmpty: emptyTrash)
        }
    }
    
}

extension GroupRowView {
    @ViewBuilder private var groupIcon: some View {
        WithViewStore(self.store, observe: \.group) { group in
            switch group.groupType {
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
        WithViewStore(self.store, observe: \.group) { group in
            if group.groupType == .normal {
                Button(role: .destructive) {
                    alertDeletion.toggle()
                } label: {
                    Label("delete", systemImage: "trash")
                }
            } else if group.groupType == .trash {
                Button(role: .destructive) {
                    alertEmpty.toggle()
                } label: {
                    Label("empty", systemImage: "trash")
                }
            }
        }
    }
}


// MARK: - Alert
fileprivate extension View {
    @ViewBuilder func deleteAlert(isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        self
            .alert("Are you sure you want to delete this folder?", isPresented: isPresented, actions: {
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


// MARK: - Side Effects
extension GroupRowView {
    func deleteGroup() {
        self.store.send(.delete)
    }
    
    func emptyTrash() {
        self.store.send(.clearFiles)
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
