//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI


struct FileRowView: View {
    @EnvironmentObject var store: AppStore
    var fileInfo: File
    
    var selected: Bool {
        return store.state.currentFile == fileInfo
    }
    
    @State private var renameMode: Bool = false
    @State private var newFilename: String = ""
    @State private var showPermanentlyDeleteAlert: Bool = false
    @State private var hovering = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        rowWrapper {
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
                        filename
                    }
                    
                }
                .font(.title3)
                .lineLimit(1)
                .padding(.bottom, 4)
                HStack {
                    Text((fileInfo.updatedAt ?? fileInfo.createdAt ?? .distantPast).formatted())
                        .font(.footnote)
                        .layoutPriority(1)
                    Spacer()
                    
                    HStack {
                        if #available(macOS 13.0, *) {
                            Image("circle.grid.2x3.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 12)
                            
                                .draggable(FileLocalizable(fileID: fileInfo.id!, groupID: fileInfo.group!.id!)) {
                                    FileRowView(fileInfo: fileInfo)
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
        }
        .onHover(perform: { hover in
            withAnimation {
                hovering = hover
            }
        })
        .onAppear {
            newFilename = fileInfo.name ?? "Untitled"
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            selected ? RoundedRectangle(cornerRadius: 4).foregroundColor(Color.accentColor.opacity(0.5)) : nil
        )
        .contextMenu {
            listRowContextMenu
        }
        .alert("Are you sure to permanently delete the file: \(fileInfo.name ?? "")", isPresented: $showPermanentlyDeleteAlert) {
            Button(role: .cancel) {
                showPermanentlyDeleteAlert.toggle()
            } label: {
                Text("Cancel")
            }
            
            Button(role: .destructive) {
                store.send(.deleteFile(fileInfo, true))
            } label: {
                Text("Delete")
            }
        }
    }
    
    @ViewBuilder private var filename: some View {
        Text(fileInfo.name ?? "Untitled")
            .layoutPriority(1)
        Text(".excalidraw")
            .opacity(0.5)
    }
    
    @ViewBuilder
    func rowWrapper<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if renameMode {
            content()
        } else {
            Button {
                store.send(.setCurrentFile(fileInfo))
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

extension FileRowView {
    /// Maybe make a global identifier for file is a better way, which will not cause `List` selection change when file name is changed.
    func renameFile() {
        renameMode.toggle()
        store.send(.renameFile(of: fileInfo, newName: newFilename))
    }
    
    func deleteFile() {
        store.send(.deleteFile(fileInfo))
    }
}

// MARK: - Context Menu
extension FileRowView {
    @ViewBuilder private var listRowContextMenu: some View {
        if !fileInfo.inTrash {
            Button {
                renameMode.toggle()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Button {
                store.send(.duplicateFile(self.fileInfo))
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            
            Button(role: .destructive) {
                deleteFile()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } else {
            Button {
                store.send(.recoverFile(fileInfo))
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

#if DEBUG
struct FileRowView_Previews: PreviewProvider {
    static var previews: some View {
        FileRowView(fileInfo: .preview)
            .frame(width: 200)
    }
}
#endif
