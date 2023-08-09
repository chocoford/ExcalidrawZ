//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture

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
        self.name = self.fileEntity.name ?? "Untitled"
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

struct FileRowStore: ReducerProtocol {
    typealias State = SidebarBaseState<_State>
    struct _State: Equatable, Identifiable {
        var id: UUID { self.file.id }
        var file: FileInfo
        var isSelected: Bool
    }
    
    enum Action: Equatable {
        case setAsCurrentFile
        case renameCurrentFile(_ newName: String)
        case moveCurrentFile(_ toGroup: Group)
        case duplicateCurrentFile
        case deleteCurrentFile
        case deletePermanentlyCurrentFile
        case recoverCurrentFile
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case willDuplicateFile(File)
            
            
            case didSetAsCurrentFile
            case didRenameCurrentFile
            case didMoveCurrentFile
            case didDeleteFile(File)
            case didRecoverFile(File)
        }
    }
    
    @Dependency(\.coreData) var coreData
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setAsCurrentFile:
//                    state.currentFile = state.file.fileEntity
                    return .send(.delegate(.didSetAsCurrentFile))
                case .renameCurrentFile(let name):
                    state.file.setName(name)
                    coreData.provider.save()
                    return .send(.delegate(.didRenameCurrentFile))
                case .duplicateCurrentFile:
                    return .send(.delegate(.willDuplicateFile(state.file.fileEntity)))
                case .moveCurrentFile(let group):
                    state.file.move(to: group)
                    coreData.provider.save()
                    return .send(.delegate(.didMoveCurrentFile))
                case .deleteCurrentFile:
                    state.file.delete()
                    coreData.provider.save()
                    return .send(.delegate(.didDeleteFile(state.file.fileEntity)))
                case .deletePermanentlyCurrentFile:
                    coreData.viewContext.delete(state.file.fileEntity)
                    coreData.provider.save()
                    return .send(.delegate(.didDeleteFile(state.file.fileEntity)))
                case .recoverCurrentFile:
                    guard state.file.inTrash else { return .none }
                    state.file.recover()
                    return .send(.delegate(.didRecoverFile(state.file.fileEntity)))
                case .delegate:
                    return .none
            }
        }
    }
}


struct FileRowView: View {
    let store: StoreOf<FileRowStore>
        
    @State private var renameMode: Bool = false
    @State private var showPermanentlyDeleteAlert: Bool = false
    @State private var isHovered = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Button {
                viewStore.send(.setAsCurrentFile)
            } label: {
                VStack(alignment: .leading) {
                    HStack {
                        Text(viewStore.file.name) //+ Text(".excalidraw")
                    }
                    .foregroundColor(.secondary)
                    .font(.title3)
                    .lineLimit(1)
                    .padding(.bottom, 4)
                    
                    HStack {
                        Text((viewStore.file.updatedAt).formatted())
                            .font(.footnote)
                            .layoutPriority(1)
                        Spacer()
                        
//                        HStack {
//                            if #available(macOS 13.0, *) {
//                                Image("circle.grid.2x3.fill")
//                                    .resizable()
//                                    .aspectRatio(contentMode: .fit)
//                                    .frame(height: 12)
//                                
//                                    .draggable(FileLocalizable(fileID: viewStore.file.id, groupID: viewStore.file.group!.id!)) {
//                                        FileRowView(store: self.store)
//                                            .frame(width: 200)
//                                            .padding(.horizontal, 4)
//                                            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
//                                    }
//                            }
//                            
//                            Menu {
//                                listRowContextMenu
//                            } label: {
//                                Image(systemName: "ellipsis.circle.fill")
//                                    .resizable()
//                            }
//                            .menuStyle(.borderlessButton)
//                            .menuIndicator(.hidden)
//                            .frame(width: 20)
//                            .padding(.horizontal, 4)
//                        }
//                        .opacity(isHovered ? 1 : 0)
                    }
                }
            }
            .onHover{ isHovered = $0 }
            .buttonStyle(ListButtonStyle(selected: viewStore.isSelected))
            .contextMenu { listRowContextMenu }
            .alert(
                "Are you sure to permanently delete the file: \(viewStore.file.name)",
                isPresented: $showPermanentlyDeleteAlert
            ) {
                Button(role: .cancel) {
                    showPermanentlyDeleteAlert.toggle()
                } label: {
                    Text("Cancel")
                }
                Button(role: .destructive) {
                    store.send(.deletePermanentlyCurrentFile)
                } label: {
                    Text("Delete permanently")
                }
            }
            .sheet(isPresented: $renameMode) {
                RenameSheetView(text: viewStore.file.name) { newName in
                    viewStore.send(.renameCurrentFile(newName))
                }
                .frame(width: 300)
            }
        }
    }
}
/*
 
 if renameMode {
     TextField(text: $newFilename) {}
         .textFieldStyle(.squareBorder)
         .contentShape(Rectangle())
         .focused($isFocused)
         .onChange(of: isFocused) { newValue in
             if !isFocused {
                 renameFile()
             }
         }
         .onSubmit {
             renameFile()
         }
 } else {
     
 }

extension FileRowView {
    func renameFile() {
        renameMode.toggle()
        store.send(.renameCurrentFile(newFilename))
    }
}
 */

// MARK: - Context Menu
extension FileRowView {
    @ViewBuilder private var listRowContextMenu: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            if !viewStore.file.inTrash {
                Button {
                    renameMode.toggle()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Button {
                    self.store.send(.duplicateCurrentFile)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                
                Menu {
                    let groups: [Group] = viewStore.groups
                        .filter{ $0.groupType != .trash }
                        .sorted { a, b in
                            a.groupType == .default && b.groupType != .default ||
                            a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast
                        }
                    ForEach(groups) { group in
                        Button {
                            self.store.send(.moveCurrentFile(group))
                        } label: {
                            Text(group.name ?? "unknown")
                        }
                        .disabled(group.id == viewStore.file.group?.id)
                    }
                } label: {
                    Label("Move to", systemImage: "arrow.up.bin")
                }
                
                Button(role: .destructive) {
                    store.send(.deleteCurrentFile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    store.send(.recoverCurrentFile)
                } label: {
                    Label("Recover", systemImage: "arrowshape.turn.up.backward.fill")
                }
                
                Button {
                    showPermanentlyDeleteAlert.toggle()
                } label: {
                    Label("Delete Permanently", systemImage: "arrowshape.turn.up.backward.fill")
                }
            }
        }
    }
}

#if DEBUG
struct FileRowView_Previews: PreviewProvider {
    static var previews: some View {
        FileRowView(
            store: .init(
                initialState: .init(
                    groups: [Group.preview],
                    currentGroup: nil,
                    state: .init(file: .init(file: File.preview), isSelected: false))
            ) {
                FileRowStore()
            }
        )
        .frame(width: 200)
    }
}
#endif
