//
//  LocalFileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/24/25.
//

import SwiftUI

import ChocofordUI

struct LocalFileRowView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var updateFlag: Date?
    
    init(file: URL, updateFlag: Date?) {
        self.file = file
        self.updateFlag = updateFlag
    }
    
    var modifiedDate: Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.filePath)
            if let modifiedDate = attributes[FileAttributeKey.modificationDate] as? Date {
                return modifiedDate
            }
        } catch {
            print(error)
        }
        
        return Date.distantPast
    }
    
    @State private var isRenameSheetPresented = false
    @State private var isDeleteConfirmationDialogPresented = false
    
    var body: some View {
        Button {
            fileState.currentLocalFile = file
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(file.deletingPathExtension().lastPathComponent)
                }
                .foregroundColor(.secondary)
                .font(.title3)
                .lineLimit(1)
                .padding(.bottom, 4)

                HStack {
                    Text(modifiedDate.formatted())
                        .font(.footnote)
                        .layoutPriority(1)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ListButtonStyle(selected: fileState.currentLocalFile == file))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .modifier(
            RenameSheetViewModifier(
                isPresented: $isRenameSheetPresented,
                name: file.deletingPathExtension().lastPathComponent
            ) { newName in
                renameFile(newName: newName)
            }
        )
//        .confirmationDialog(
//            "Are you sure to delete the file?",
//            isPresented: $isDeleteConfirmationDialogPresented,
//            titleVisibility: .automatic
//        ) {
//            Button(role: .destructive) {
//                do {
//                    if let folder = fileState.currentLocalFolder {
//                        try folder.withSecurityScopedURL { _ in
//                            try FileManager.default.removeItem(at: file)
//                        }
//                    }
//                } catch {
//                    alertToast(error)
//                }
//            } label: {
//                Text("Confirm")
//            }
//        } message: {
//            Text("You can not revert this changes")
//        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        // Rename
        Button {
            isRenameSheetPresented.toggle()
        } label: {
            Label("Rename...", systemSymbol: .squareAndPencil)
                .foregroundStyle(.red)
        }

        Button {
            do {
                guard let folder = fileState.currentLocalFolder else { return }
                try folder.withSecurityScopedURL { scopedURL in
                    let file = try ExcalidrawFile(contentsOf: file)
                    
                    var newFileName = self.file.deletingPathExtension().lastPathComponent
                    while FileManager.default.fileExists(at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)) {
                        let components = newFileName.components(separatedBy: "-")
                        if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                            newFileName = "\(components[0])-\(index+1)"
                        } else {
                            newFileName = "\(newFileName)-1"
                        }
                    }
                    
                    let newURL = self.file.deletingLastPathComponent().appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
                    
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(writingItemAt: newURL, options: .forReplacing, error: nil) { url in
                        do {
                            try file.content?.write(to: url)
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            } catch {
                
            }
        } label: {
            Label("Duplicate", systemSymbol: .docOnDoc)
                .foregroundStyle(.red)
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.file.filePath, forType: .string)
        } label: {
            Label("Copy File Path", systemSymbol: .arrowRightDocOnClipboard)
                .foregroundStyle(.red)
        }
        
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([self.file])
        } label: {
            Label("Reveal in Finder", systemSymbol: .docViewfinder)
                .foregroundStyle(.red)
        }
        
        Divider()
        
        // Delete
        Button {
            do {
                if let folder = fileState.currentLocalFolder {
                    try folder.withSecurityScopedURL { _ in
                        // Item removed will be handled in `LocalFilesListView`
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(
                            writingItemAt: file,
                            options: .forDeleting,
                            error: nil
                        ) { url in
                            do {
                                try FileManager.default.trashItem(
                                    at: url,
                                    resultingItemURL: nil
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
            } catch {
                alertToast(error)
            }
        } label: {
            Label("Move to Trash", systemSymbol: .trash)
                .foregroundStyle(.red)
        }
    }
    
    private func renameFile(newName: String) {
        do {
            if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { _ in
                    let newURL = file.deletingLastPathComponent()
                        .appendingPathComponent(
                            newName,
                            conformingTo: .excalidrawFile
                        )
                    try FileManager.default.moveItem(at: file, to: newURL)
                    
                    ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                    self.fileState.currentLocalFile = newURL
                    ExcalidrawFile.localFileURLIDMapping[file] = nil
                }
            }
        } catch {
            alertToast(error)
        }
    }
}

