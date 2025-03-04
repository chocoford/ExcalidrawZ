//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import CoreData
import ChocofordUI

struct FileInfo: Equatable {
    private(set) var fileEntity: File
    
    // file info
    private(set) var id: UUID {
        willSet { self.fileEntity.id = newValue }
    }
    private(set) var name: String {
        willSet { self.fileEntity.name = newValue }
    }
    private(set) var createdAt: Date {
        willSet { self.fileEntity.createdAt = newValue }
    }
    private(set) var updatedAt: Date {
        willSet { self.fileEntity.updatedAt = newValue }
    }
    private(set) var deletedAt: Date? {
        willSet { self.fileEntity.deletedAt = newValue }
    }
    private(set) var inTrash: Bool {
        willSet { self.fileEntity.inTrash = newValue }
    }
    private(set) var content: Data? {
        willSet { self.fileEntity.content = newValue }
    }
    
    // relation
    var group: Group? {
        willSet { self.fileEntity.group = newValue }
    }
    
    init(file fileEntity: File) {
        self.fileEntity = fileEntity
        
        self.id = self.fileEntity.id ?? UUID()
        self.name = self.fileEntity.name ?? String(localizable: .newFileNamePlaceholder)
        self.createdAt = self.fileEntity.createdAt ?? .distantPast
        self.updatedAt = self.fileEntity.updatedAt ?? self.createdAt
        self.deletedAt = self.fileEntity.deletedAt
        self.inTrash = self.fileEntity.inTrash
        self.content = self.fileEntity.content
        self.group = self.fileEntity.group
    }
    
    
    public mutating func setName(_ newName: String) {
        self.name = newName
    }
    
    public mutating func move(to group: Group) {
        self.group = group
        self.updatedAt = .now
    }
    
    public mutating func delete() {
        self.inTrash = true
        self.deletedAt = .now
    }
    
    public mutating func recover() {
        self.inTrash = false
        self.deletedAt = nil
    }
}

struct FileRowView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: File
    @Binding var fileIDToBeRenamed: NSManagedObjectID?
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>
        
    init(file: File, fileIDToBeRenamed: Binding<NSManagedObjectID?>) {
        self.file = file
        self._fileIDToBeRenamed = fileIDToBeRenamed
    }
    
    @State private var showPermanentlyDeleteAlert: Bool = false
    @State private var isHovered = false
    
    @FocusState private var isFocused: Bool
    
    var isSelected: Bool {
        fileState.currentFile == file
    }
    
    var body: some View {
        Button {
            fileState.currentFile = file
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(file.name ?? "")
                }
                .foregroundColor(.secondary)
                .font(.title3)
                .lineLimit(1)
                .padding(.bottom, 4)
                
                HStack {
                    Text((file.updatedAt ?? .distantPast).formatted())
                        .font(.footnote)
                        .layoutPriority(1)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .onHover{ isHovered = $0 }
        .buttonStyle(ListButtonStyle(selected: isSelected))
        .contextMenu { listRowContextMenu.labelStyle(.titleAndIcon) }
        .confirmationDialog(
            LocalizedStringKey.localizable(.sidebarFileRowDeletePermanentlyAlertTitle(file.name ?? "")),
            isPresented: $showPermanentlyDeleteAlert
        ) {
            Button(role: .destructive) {
                fileState.deleteFilePermanently(file)
            } label: {
                Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm))
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
    }
    
    // Context Menu
    @MainActor @ViewBuilder
    private var listRowContextMenu: some View {
        if !file.inTrash {
            Button {
                fileIDToBeRenamed = self.file.objectID
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .pencil)
            }
            
            Button {
                do {
                    let newFile = try fileState.duplicateFile(file, context: managedObjectContext)
                    if containerHorizontalSizeClass != .compact {
                        fileState.currentFile = newFile
                    }
                } catch {
                    alertToast(error)
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDuplicate), systemSymbol: .docOnDoc)
            }
             
            moveFileMenu()
            
            Button(role: .destructive) {
                fileState.deleteFile(file)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDelete), systemSymbol: .trash)
            }
            
        } else {
            Button {
                fileState.recoverFile(file)
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuRecover),
                    systemSymbol: .arrowshapeTurnUpBackward
                )
                .symbolVariant(.fill)
            }
            
            Button {
                showPermanentlyDeleteAlert.toggle()
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuDeletePermanently),
                    systemSymbol: .trash
                )
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func actions() -> some View {
        HStack {
            if #available(macOS 13.0, *) {
                Image("circle.grid.2x3.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 12)
//                    .draggable(FileLocalizable(fileID: file.id, groupID: file.group!.id!)) {
//                        FileRowView(store: self.store)
//                            .frame(width: 200)
//                            .padding(.horizontal, 4)
//                            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
//                    }
            }
            
            Menu {
                listRowContextMenu
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .resizable()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .padding(.horizontal, 4)
        }
        .opacity(isHovered ? 1 : 0)
    }
    
    @MainActor @ViewBuilder
    private func moveFileMenu() -> some View {
        if let sourceGroup = file.group {
            Menu {
                let groups: [Group] = topLevelGroups
                    .filter{ $0.groupType != .trash }
                    .sorted { a, b in
                        a.groupType == .default && b.groupType != .default ||
                        a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast
                    }
                ForEach(groups) { group in
                    MoveToGroupMenu(
                        destination: group,
                        sourceGroup: sourceGroup,
                        childrenSortKey: \Group.name,
                        allowSubgroups: true
                    ) { targetGroupID in
                        moveFile(to: targetGroupID)
                    }
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .trayAndArrowUp)
            }
        }
    }
    
    private func moveFile(to groupID: NSManagedObjectID) {
        Task {
            do {
                try await fileState.moveFile(
                    file.objectID,
                    to: groupID,
                    context: PersistenceController.shared.container.newBackgroundContext()
                )
            } catch {
                alertToast(error)
            }
        }
    }
}


#if DEBUG
//struct FileRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        FileRowView(groups: <#T##FetchedResults<Group>#>, file: <#T##File#>)
//        .frame(width: 200)
//    }
//}
#endif
