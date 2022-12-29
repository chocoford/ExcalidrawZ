//
//  FileRowView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI

enum RenameError: LocalizedError {
    case unexpected(_ error: Error?)
    case notFound
    
    var errorDescription: String? {
        switch self {
            case .notFound:
                return "File not found."
                
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
                
        }
    }
}

struct FileRowView: View {
    @EnvironmentObject var store: AppStore
    var fileInfo: FileInfo
    
    @State private var renameMode: Bool = false
    @State private var newFilename: String = ""
    @State private var renameHasError: Bool = false
    @State private var renameError: RenameError? = nil
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
        .alert(isPresented: $renameHasError, error: renameError) {
            
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
    func renameFile() {
        renameMode.toggle()
        do {
            let url = try AppFileManager.shared.renameFile(fileInfo.url, to: newFilename)
            print("===============rename file - setCurrentFile \(url.lastPathComponent.description)")
            DispatchQueue.main.async {
                store.send(.setCurrentFile(url))
            }
        } catch {
            renameHasError = true
            renameError = .unexpected(error)
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
