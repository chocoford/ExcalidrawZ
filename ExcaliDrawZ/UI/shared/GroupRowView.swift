//
//  GroupRowView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI

struct GroupRowView: View {
    @EnvironmentObject var store: AppStore
    
    var group: Group
    
    @State private var alertDeletion = false
    
    var body: some View {
        NavigationLink(value: group, label: {
            Label { Text(group.name ?? "Untitled") } icon: { groupIcon }
        })
        .if(group.groupType != .trash, transform: { content in
            content
                .dropDestination(for: FileLocalizable.self) { fileInfos, location in
                    guard let file = fileInfos.first else { return false }
                    store.send(.moveFile(file.fileID, group))
                    return true
                }
        })
        .contextMenu { contextMenuView }
        .deleteAlert(isPresented: $alertDeletion, onDelete: deleteGroup)
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
        }
    }
}


// MARK: - Alert
fileprivate extension View {
    @ViewBuilder func deleteAlert(isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        self
            .alert("Are you sure you want to delete this folder?", isPresented: isPresented, actions: {
                Button(role: .cancel) {
                    
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
}


// MARK: - Side Effects
extension GroupRowView {
    func deleteGroup() {
        store.send(.deleteGroup(group))
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
