//
//  ExcalidrawFileBrowser.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/14/25.
//

import SwiftUI

struct ExcalidrawFileBrowser: View {
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var fileState = FileState()
    
    enum ActionPayload {
        case file(File)
        case localFile(URL)
    }
    var action: (ActionPayload) -> Void
    
    init(selectAction: @escaping (_ selection: ActionPayload) -> Void) {
        self.action = selectAction
    }
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 200)
            Divider()
            
            content()
                .frame(width: 460)
        }
        .frame(height: 400)
        .environmentObject(fileState)
        .onAppear {
            Task {
                try? await fileState.setToDefaultGroup()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func sidebar() -> some View {
        ExcalidrawGroupBrowser()
        .background {
            if #available(macOS 14.0, *) {
                Rectangle().fill(.windowBackground)
            } else {
                Rectangle().fill(Color.windowBackgroundColor)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 100))], spacing: 0) {
                    if let group = fileState.currentGroup {
                        ExcalidrawFileBrowserContentView(group: group) {
                            if let file = fileState.currentFile {
                                dismiss()
                                self.action(.file(file))
                                
                            }
                        }
                    } else if let folder = fileState.currentLocalFolder {
                        ExcalidrawLocalFileBrowserContentView(folder: folder) {
                            if let file = fileState.currentLocalFile {
                                dismiss()
                                self.action(.localFile(file))
                            }
                        }
                    }
                }
                .padding()
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            fileState.currentFile = nil
                            fileState.currentLocalFile = nil
                        }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button(role: .cancel) {
                     dismiss()
                } label: {
                    Text("Cancel")
                        .padding(.horizontal)
                }
                Button {
                    dismiss()
                    if let file = fileState.currentFile {
                        action(.file(file))
                    } else if let localFile = fileState.currentLocalFile {
                        action(.localFile(localFile))
                    }
                    
                } label: {
                    Text("Create")
                        .padding(.horizontal)
                }
                .buttonStyle(.borderedProminent)
                .disabled(fileState.currentFile == nil && fileState.currentLocalFile == nil)
            }
            .padding()
        }
    }
}

struct ExcalidrawFileBrowserContentView: View {
    @EnvironmentObject private var fileState: FileState
    
    @FetchRequest
    private var files: FetchedResults<File>
    var onDoubleClick: (() -> Void)?

    init(group: Group, onDoubleClick: (() -> Void)? = nil) {
        let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
        fileFetchRequest.predicate = NSPredicate(format: "group = %@ AND inTrash = false", group)
        fileFetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \File.updatedAt, ascending: false)
        ]
        self._files = FetchRequest(fetchRequest: fileFetchRequest, animation: .default)
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var fileIcon: Image?
    
    var body: some View {
        ForEach(files) { file in
            ExcalidrawFileItemView(
                isSelected: Binding {
                    fileState.currentFile == file
                } set: { val in
                    if val {
                        fileState.currentFile = file
                    }
                },
                filename: file.name ?? String(localizable: .generalUnknown)
            ) {
                NSWorkspace.shared.icon(for: .excalidrawFile)
            } onDoubleClick: {
                onDoubleClick?()
            }
        }
    }
}


struct ExcalidrawLocalFileBrowserContentView: View {
    @EnvironmentObject private var fileState: FileState
    
    var folder: LocalFolder
    var onDoubleClick: (() -> Void)?
    
    init(folder: LocalFolder, onDoubleClick: (() -> Void)? = nil) {
        self.folder = folder
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var contents: [URL] = []
    
    var body: some View {
        ForEach(contents, id: \.self) { url in
            ExcalidrawFileItemView(
                isSelected: Binding {
                    fileState.currentLocalFile == url
                } set: { val in
                    if val {
                        fileState.currentLocalFile = url
                    }
                },
                filename: url.lastPathComponent
            ) {
                NSWorkspace.shared.icon(forFile: url.filePath)
            } onDoubleClick: {
                onDoubleClick?()
            }
        }
    }
}

struct ExcalidrawFileItemView: View {
    
    @Binding var isSelected: Bool
    
    var filename: String
    var fileIconGenerator: () -> NSImage
    var onDoubleClick: (() -> Void)?
    
    init(
        isSelected: Binding<Bool>,
        filename: String,
        fileIconGenerator: @escaping () -> NSImage,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self._isSelected = isSelected
        self.filename = filename
        self.fileIconGenerator = fileIconGenerator
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var fileIcon: Image?
    
    var body: some View {
        VStack(spacing: 6) {
            (fileIcon ?? Image(systemSymbol: .doc))
                .resizable()
                .scaledToFit()
                .padding(4)
                .frame(height: 60)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                }
            
            Text(filename)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .font(.callout)
                .padding(2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? AnyShapeStyle(Color.accent) : AnyShapeStyle(Color.clear))
                }
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 40, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            isSelected = true
            onDoubleClick?()
        }
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                isSelected = true
            }
        )
        .opacity(fileIcon != nil ? 1 : 0)
        .onAppear {
            Task.detached {
                let image = await Image(nsImage: fileIconGenerator())
                await MainActor.run {
                    self.fileIcon = image
                }
            }
        }
    }
}

#Preview {
    ExcalidrawFileBrowser { selection in
        
    }
}
