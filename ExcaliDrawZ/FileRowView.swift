//
//  FileRowView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI


struct FileRowView: View {
    @EnvironmentObject var store: AppStore
    var fileInfo: FileInfo
    
    @State private var renameMode: Bool = false
    @State private var newFilename: String = ""
    @State private var hasError: Bool = false
    @State private var error: AppError? = nil
    
    @State private var showDeleteAlert: Bool = false
    
    @FocusState private var isFocused: Bool

    var body: some View {
        rowWrapper {
            VStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if renameMode {
                        TextField(text: $newFilename) {
                            
                        }
                        .textFieldStyle(.squareBorder)
                        .contentShape(Rectangle())
                        .focused($isFocused)
                        .onChange(of: isFocused) { newValue in
                            if !isFocused {
                                renameFile()
                            }
                        }
                    } else {
                        filename
                    }
                    
                }
                .font(.headline)
                .fontWeight(.medium)
                
                HStack {
                    Text((fileInfo.updatedAt ?? .distantPast).formatted())
                        .font(.footnote)
                    Spacer()
                    Text(fileInfo.size ?? "")
                        .font(.footnote)
                }
            }
        }
        .onAppear {
            newFilename = fileInfo.name ?? "Untitled"
        }
        .padding(.vertical)
        .contextMenu {
            listRowContextMenu
        }
        .alert(isPresented: $hasError, error: error) {
            
        }
        .alert("Are you sure to delete file: \(fileInfo.name ?? "")", isPresented: $showDeleteAlert) {
            Button(role: .cancel) {
                showDeleteAlert.toggle()
            } label: {
                Text("Cancel")
            }
            
            Button(role: .destructive) {
                deleteFile()
            } label: {
                Text("Delete")
            }
        }
    }
    
    @ViewBuilder private var filename: some View {
        Text(fileInfo.name ?? "Untitled")
            .layoutPriority(1)
        Text("." + (fileInfo.fileExtension ?? ""))
            .opacity(0.5)
    }
    
    @ViewBuilder
    func rowWrapper<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if renameMode {
                content()
        } else {
            NavigationLink(value: fileInfo.url) {
                content()
            }
        }
    }
}

extension FileRowView {
    /// Maybe make a global identifier for file is a better way, which will not cause `List` selection change when file name is changed.
    func renameFile() {
        renameMode.toggle()
        var isCurrentFile = false
        if fileInfo.url == store.state.currentFile {
            isCurrentFile = true
        }
        do {
            // It will trigger file info change. Causing `List` change its selection.
            // But the procedure is not synchronizign.
            let url = try AppFileManager.shared.renameFile(fileInfo.url, to: newFilename)
            
            if isCurrentFile {
                // Use async on main thread to make sure `setCurrentFile` will execute after `List`'s selection changing.
                DispatchQueue.main.async {
                    store.send(.setCurrentFile(url))
                }
            }
        } catch {
            hasError = true
            self.error = .renameError(.unexpected(error))
        }
    }
    
    func deleteFile() {
        do {
            try AppFileManager.shared.removeFile(at: fileInfo.url)
            store.send(.setCurrentFile(AppFileManager.shared.assetFiles.first?.url))
        } catch {
            hasError = true
            self.error = .deleteError(.unexpected(error))
        }
    }
}

// MARK: - Context Menu
extension FileRowView {
    @ViewBuilder private var listRowContextMenu: some View {
        Button {
            renameMode.toggle()
        } label: {
            Text("Rename")
        }
        
        Button(role: .destructive) {
            showDeleteAlert.toggle()
        } label: {
            Text("Delete")
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
