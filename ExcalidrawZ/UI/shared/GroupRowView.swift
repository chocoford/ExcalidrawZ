//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI

struct GroupRowView: View {
    @EnvironmentObject var store: AppStore
    
    var group: Group
    
    var selected: Bool {
        return store.state.currentGroup == group
    }
    
    @State private var alertDeletion = false
    @State private var alertEmpty = false
    
    var body: some View {
        if group.groupType != .trash {
            if #available(macOS 13.0, *) {
                content
                    .dropDestination(for: FileLocalizable.self) { fileInfos, location in
                        guard let file = fileInfos.first else { return false }
                        store.send(.moveFile(file.fileID, group))
                        return true
                    }
            } else {
                content
            }
        } else {
            content
        }
    }
    
    @ViewBuilder private var content: some View {
        Button {
            store.send(.setCurrentGroup(group))
        } label: {
            HStack {
                Label { Text(group.name ?? "Untitled").lineLimit(1) } icon: { groupIcon }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            selected ? RoundedRectangle(cornerRadius: 4).foregroundColor(Color.accentColor.opacity(0.5)) : nil
        )
        .contextMenu { contextMenuView }
        .deleteAlert(isPresented: $alertDeletion, onDelete: deleteGroup)
        .emptyAlert(isPresented: $alertEmpty, onEmpty: emptyTrash)
    }
    
}

extension GroupRowView {
    @ViewBuilder private var groupIcon: some View {
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


// MARK: - Context Menu
extension GroupRowView {
    @ViewBuilder private var contextMenuView: some View {
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
        store.send(.deleteGroup(group))
    }
    
    func emptyTrash() {
        store.send(.emptyTrash)
    }
}

#if DEBUG
struct GroupRowView_Previews: PreviewProvider {
    static var previews: some View {
        GroupRowView(group: .preview)
            .environmentObject(AppStore.preview)
    }
}
#endif
