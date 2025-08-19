//
//  LocalFiles+Drop.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/18/25.
//

import SwiftUI

//struct LocalFilesDropModifier: ViewModifier {
//    @Environment(\.managedObjectContext) private var viewContext
//    @Environment(\.alertToast) private var alertToast
//    
//    @EnvironmentObject private var fileState: FileState
//    @EnvironmentObject private var localFolderState: LocalFolderState
//    
//    var folder: LocalFolder
//    
//    @Binding var isTargeted: Bool
//    
//    @State private var groupIDWillBeDropped: NSManagedObjectID?
//    @State private var fileIDWillBeDropped: NSManagedObjectID?
//    
//    func body(content: Content) -> some View {
//        content
//            .modifier(
//                SidebarGroupRowDropModifier(
//                    isTargeted: $isTargeted,
//                    onDrop: { item in
//                        switch item {
//                            case .group(let groupID):
//                                handleDropGroup(id: groupID)
//                            case .file(let fileID):
//                                handleDropFile(id: fileID)
//                            case .localFolder(let folderID):
//                                handleDropLocalFolder(id: folderID)
//                            case .localFile(let url):
//                                break
//                        }
//                    }
//                )
//            )
//            .confirmationDialog(
//                "Export to disk",
//                isPresented: Binding {
//                    groupIDWillBeDropped != nil
//                } set: {
//                    if !$0 { groupIDWillBeDropped = nil }
//                }
//            ) {
//                Button {
//                    performDropGroup(id: groupIDWillBeDropped!)
//                } label: {
//                    Text(.localizable(.generalButtonConfirm))
//                }
//            } message: {
//                Text("This will export the group and its contents to the folder.")
//            }
//            .confirmationDialog(
//                "Export to dist",
//                isPresented: Binding {
//                    fileIDWillBeDropped != nil
//                } set: {
//                    if !$0 { fileIDWillBeDropped = nil }
//                }
//            ) {
//                Button {
//                    performDropFile(id: fileIDWillBeDropped!)
//                } label: {
//                    Text(.localizable(.generalButtonConfirm))
//                }
//            } message: {
//                Text("This will export the file to the folder.")
//            }
//        
//    }
//    
//    
//    private func handleDropGroup(id: NSManagedObjectID) {
//        self.groupIDWillBeDropped = id
//    }
//    
//    private func performDropGroup(id: NSManagedObjectID) {
//        guard let group = viewContext.object(with: id) as? Group,
//              let url = folder.url else { return }
//        group.exportToDisk(folder: url)
//    }
//    
//    private func handleDropFile(id: NSManagedObjectID) {
//        self.fileIDWillBeDropped = id
//    }
//    
//    private func performDropFile(id: NSManagedObjectID) {
//        guard let file = viewContext.object(with: id) as? File,
//        let url = folder.url else { return }
//        file.exportToDisk(folder: url)
//    }
//    
//    private func handleDropLocalFolder(id: NSManagedObjectID) {
//        guard let folder = viewContext.object(with: id) as? LocalFolder else { return }
//        do {
//            try localFolderState.moveLocalFolder(
//                id,
//                to: folder.objectID,
//                forceRefreshFiles: true,
//                context: viewContext
//            )
//        } catch {
//            alertToast(error)
//        }
//    }
//    
//    private func handleDropLocalFile(url: URL) {
//        do {
//            let mapping = try localFolderState.moveLocalFiles(
//                [url],
//                to: folder.objectID,
//                context: viewContext
//            )
//            
//            if fileState.currentActiveFile == .localFile(url), let newURL = mapping[url] {
//                fileState.currentActiveGroup = .localFolder(folder)
//                fileState.currentActiveFile = .localFile(newURL)
//                fileState.expandToGroup(folder.objectID)
//            }
//        } catch {
//            alertToast(error)
//        }
//    }
//}
