//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import ComposableArchitecture

struct FileRowStore: ReducerProtocol {
    struct State: Equatable, Identifiable {
        var id: UUID { self.file.id ?? UUID() }
        var file: File
        var isSelected: Bool
    }
    
    enum Action: Equatable {
        case setCurrentFile
        case renameCurrentFile(_ newName: String)
        case duplicateCurrentFile
        case deleteCurrentFile
        case recoverCurrentFile
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            return .none
        }
    }
}


struct FileRowView: View {
    let store: StoreOf<FileRowStore>
    
    @State private var renameMode: Bool = false
    @State private var newFilename: String = ""
    @State private var showPermanentlyDeleteAlert: Bool = false
    @State private var hovering = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        if renameMode {
            content()
        } else {
            Button {
                self.store.send(.setCurrentFile)
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            VStack(alignment: .leading) {
                HStack(spacing: 0) {
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
                        Text(viewStore.file.name ?? "Untitled") + Text(".excalidraw").foregroundColor(.secondary)
                    }
                    
                }
                .font(.title3)
                .lineLimit(1)
                .padding(.bottom, 4)
                HStack {
                    Text((viewStore.file.updatedAt ?? viewStore.file.createdAt ?? .distantPast).formatted())
                        .font(.footnote)
                        .layoutPriority(1)
                    Spacer()
                    
                    HStack {
                        if #available(macOS 13.0, *) {
                            Image("circle.grid.2x3.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 12)
                            
                                .draggable(FileLocalizable(fileID: viewStore.file.id!, groupID: viewStore.file.group!.id!)) {
                                    FileRowView(store: self.store)
                                        .frame(width: 200)
                                        .padding(.horizontal, 4)
                                        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
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
                    .opacity(hovering ? 1 : 0)
                }
            }
            .onHover(perform: { hover in
                withAnimation {
                    hovering = hover
                }
            })
            .onAppear {
                newFilename = viewStore.file.name ?? "Untitled"
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                viewStore.isSelected ? RoundedRectangle(cornerRadius: 4).foregroundColor(Color.accentColor.opacity(0.5)) : nil
            )
            .contextMenu {
                listRowContextMenu
            }
            .alert("Are you sure to permanently delete the file: \(viewStore.file.name ?? "")", isPresented: $showPermanentlyDeleteAlert) {
                Button(role: .cancel) {
                    showPermanentlyDeleteAlert.toggle()
                } label: {
                    Text("Cancel")
                }
                
                Button(role: .destructive) {
                    store.send(.deleteCurrentFile)
                } label: {
                    Text("Delete")
                }
            }
        }
    }
}

extension FileRowView {
    func renameFile() {
        renameMode.toggle()
        store.send(.renameCurrentFile(newFilename))
    }
}

// MARK: - Context Menu
extension FileRowView {
    @ViewBuilder private var listRowContextMenu: some View {
        WithViewStore(self.store, observe: \.file) { file in
            if !file.inTrash {
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
            store: .init(initialState: .init(file: .preview, isSelected: false),
                         reducer: { FileRowStore() })
        )
        .frame(width: 200)
    }
}
#endif
