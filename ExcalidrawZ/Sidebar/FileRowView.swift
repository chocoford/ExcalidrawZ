//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
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
    @EnvironmentObject var fileState: FileState
    
    var groups: FetchedResults<Group>
    var file: File
        
    init(groups: FetchedResults<Group>, file: File) {
        self.groups = groups
        self.file = file
    }
    
    @State private var renameMode: Bool = false
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
                    
//                    HStack {
//                        if #available(macOS 13.0, *) {
//                            Image("circle.grid.2x3.fill")
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(height: 12)
//
//                                .draggable(FileLocalizable(fileID: viewStore.file.id, groupID: viewStore.file.group!.id!)) {
//                                    FileRowView(store: self.store)
//                                        .frame(width: 200)
//                                        .padding(.horizontal, 4)
//                                        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
//                                }
//                        }
//
//                        Menu {
//                            listRowContextMenu
//                        } label: {
//                            Image(systemName: "ellipsis.circle.fill")
//                                .resizable()
//                        }
//                        .menuStyle(.borderlessButton)
//                        .menuIndicator(.hidden)
//                        .frame(width: 20)
//                        .padding(.horizontal, 4)
//                    }
//                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .onHover{ isHovered = $0 }
        .buttonStyle(ListButtonStyle(selected: isSelected))
        .contextMenu { listRowContextMenu }
        .alert(
            LocalizedStringKey.localizable(.sidebarFileRowDeletePermanentlyAlertTitle(file.name ?? "")),
            isPresented: $showPermanentlyDeleteAlert
        ) {
            Button(role: .cancel) {
                showPermanentlyDeleteAlert.toggle()
            } label: {
                Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonCancel))
            }
            Button(role: .destructive) {
                fileState.deleteFilePermanently(file)
            } label: {
                Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm))
            }
        }
        .sheet(isPresented: $renameMode) {
            RenameSheetView(text: file.name ?? "") { newName in
                fileState.renameFile(file, newName: newName)
            }
            .frame(width: 300)
        }
    }
    
    
    // Context Menu
    @MainActor @ViewBuilder
    private var listRowContextMenu: some View {
        if !file.inTrash {
            Button {
                renameMode.toggle()
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .pencil)
            }
            
            Button {
                fileState.duplicateFile(file)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDuplicate), systemSymbol: .docOnDoc)
            }
            
            Menu {
                let groups: [Group] = groups
                    .filter{ $0.groupType != .trash }
                    .sorted { a, b in
                        a.groupType == .default && b.groupType != .default ||
                        a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast
                    }
                ForEach(groups) { group in
                    Button {
                        fileState.moveFile(file, to: group)
                    } label: {
                        Text(group.name ?? "unknown")
                    }
                    .disabled(group.id == file.group?.id)
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .arrowUpBin)
            }
            
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
}


#if DEBUG
//struct FileRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        FileRowView(groups: <#T##FetchedResults<Group>#>, file: <#T##File#>)
//        .frame(width: 200)
//    }
//}
#endif
