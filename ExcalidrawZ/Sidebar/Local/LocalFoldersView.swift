//
//  LocalFoldersView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFoldersView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    
    var folder: LocalFolder
    var onDeleteSelected: () -> Void
        
    @FetchRequest
    private var folderChildren: FetchedResults<LocalFolder>
    
    init(folder: LocalFolder, onDeleteSelected: @escaping () -> Void) {
        self.folder = folder
        self._folderChildren = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true),
                NSSortDescriptor(keyPath: \LocalFolder.rank, ascending: true),
            ],
            predicate: NSPredicate(format: "parent = %@", folder),
            animation: .default
        )
        self.onDeleteSelected = onDeleteSelected
    }
    
    let paddingBase: CGFloat = 14
    
    var isSelected: Bool {
        fileState.currentLocalFolder == folder
//        if let currentLocalFolder = fileState.currentLocalFolder {
//            return currentLocalFolder.url == folder.url
//        } else {
//            return false
//        }
    }
    
    @State private var isExpanded = false
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, *), folderStructStyle == .disclosureGroup {
                diclsureGroupView()
            } else {
                treeView()
            }
        }
        .animation(.smooth, value: folderStructStyle)
    }
    
    @available(macOS 13.0, *)
    @MainActor @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: Binding {
                isSelected
            } set: {
                if $0 { fileState.currentLocalFolder = folder }
            },
            isExpanded: $isExpanded
        ) {
            ForEach(folderChildren) { folder in
                LocalFoldersView(folder: folder) {
                    handleSelectedDeletion()
                }
            }
        } label: {
            LocalFolderRowView(folder: folder, onDelete: onDeleteSelected)
        }
        .disclosureGroupIndicatorVisibility(folderChildren.isEmpty ? .hidden : .visible)
        .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
            guard let targetGroupID = notification.object as? NSManagedObjectID,
                  targetGroupID == self.folder.objectID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.isExpanded = true
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func treeView() -> some View {
        TreeStructureView(
            children: folderChildren,
            paddingLeading: 6
        ) {
            LocalFolderRowView(folder: folder, onDelete: onDeleteSelected)
        } childView: { child in
            LocalFoldersView(folder: child) {
                handleSelectedDeletion()
            }
        }
    }
    
    private func handleSelectedDeletion() {
        // switch current folder first if necessary.
        if fileState.currentLocalFolder == folder {
            guard let index = folderChildren.firstIndex(of: folder) else {
                return
            }
            if index == 0 {
                if folderChildren.count > 1 {
                    fileState.currentLocalFolder = folderChildren[1]
                } else {
                    fileState.currentLocalFolder = nil
                }
            } else {
                fileState.currentLocalFolder = folderChildren[0]
            }
        }
    }
    
}

