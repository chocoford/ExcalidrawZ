//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI

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

struct GroupRowView: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var groups: [Group]
    var group: Group
    
    init(group: Group, groups: [Group]) {
        self.group = group
        self.groups = groups
    }
    
    @State private var isDeleteConfirmPresented = false
    @State private var isRenameSheetPresented = false
    
    var isSelected: Bool { fileState.currentGroup == group }

    var body: some View {
        if group.groupType != .trash {
            if #available(macOS 13.0, *) {
                content
                    .dropDestination(for: FileLocalizable.self) { fileInfos, location in
                        guard let file = fileInfos.first else { return false }
                        // viewStore.send(.moveFileToGroup(fileID: file.fileID))
                        return true
                    }
            } else {
                content
            }
        } else {
            content
        }
    }
    
    @MainActor
    @ViewBuilder private var content: some View {
        Button {
            fileState.currentGroup = group
        } label: {
            HStack {
                Label { Text(group.name ?? "Untitled").lineLimit(1) } icon: { groupIcon }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ListButtonStyle(selected: isSelected))
        .contextMenu { contextMenuView }
        .confirmationDialog(
            group.groupType == .trash ? "Are you sure you want to permanently erase the items in the Trash?" :  "Are you sure to delete the folder \(group.name ?? "Untitled")?",
            isPresented: $isDeleteConfirmPresented
        ) {
            Button(group.groupType == .trash ? "Empty Trash" :  "Delete", role: .destructive) {
                // Handle empty trash action.
                do {
                    try fileState.deleteGroup(group)
                } catch {
                    alertToast(error)
                }
            }
        } message: {
            Text("You can’t undo this action.")
        }
        .sheet(isPresented: $isRenameSheetPresented) {
            RenameSheetView(text: group.name ?? "") { newName in
                fileState.renameGroup(group, newName: newName)
            }
        }
    }
    
}

extension GroupRowView {
    @MainActor @ViewBuilder
    private var groupIcon: some View {
        switch group.groupType {
            case .`default`:
                Image(systemName: "folder")
            case .trash:
                Image(systemName: "trash")
            case .normal:
                Image(systemName: group.icon ?? "folder")
        }
    }
    
    // MARK: - Context Menu
    @MainActor @ViewBuilder
    private var contextMenuView: some View {
        ZStack {
            if group.groupType == .normal {
                Button {
                    isRenameSheetPresented.toggle()
                } label: {
                    Label("rename", systemImage: "pencil.line")
                }
                
                Menu {
                    ForEach(groups.filter{$0 != group}) { group in
                        Button {
                            mergeWithGroup(group)
                        } label: {
                            Text(group.name ?? "Unknown")
                        }
                    }
                } label: {
                    Label("merge with", systemSymbol: .rectangleStackBadgePlus)
                }
                
                Button(role: .destructive) {
                    isDeleteConfirmPresented.toggle()
                } label: {
                    Label("delete", systemImage: "trash")
                }
            } else if group.groupType == .trash {
                Button(role: .destructive) {
                    isDeleteConfirmPresented.toggle()
                } label: {
                    Label("empty", systemImage: "trash")
                }
            } else if group.groupType == .default {
                Button {
                    isRenameSheetPresented.toggle()
                } label: {
                    Label("rename", systemImage: "pencil.line")
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
    
    private func mergeWithGroup(_ group: Group) {
        guard let files = self.group.files?.allObjects as? [File] else { return }
        fileState.currentGroup = group
        PersistenceController.shared.container.viewContext.performAndWait {
            for file in files {
                file.group = group
            }
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                print(error)
            }
        }
        let groupID = self.group.objectID
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            guard let selfGroup = bgContext.object(with: groupID) as? Group else { return }
            for file in selfGroup.files?.allObjects as? [File] ?? [] {
                bgContext.delete(file)
            }
            bgContext.delete(selfGroup)
            do {
                try bgContext.save()
            } catch {
                print(error)
            }
        }
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
//struct GroupRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack(spacing: 20) {
//            GroupRowView(
//                store: .init(initialState: .init(group: .preview, isSelected: false)) {
//                    GroupRowStore()
//                }
//            )
//            
//            GroupRowView(
//                store: .init(initialState: .init(group: .preview, isSelected: true)) {
//                    GroupRowStore()
//                }
//            )
//        }
//        .padding()
//    }
//}
#endif
