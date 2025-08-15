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
    var sortField: ExcalidrawFileSortField
    var onDeleteSelected: () -> Void
        
    @FetchRequest
    private var folderChildren: FetchedResults<LocalFolder>
    
    init(folder: LocalFolder,
         sortField: ExcalidrawFileSortField,
         onDeleteSelected: @escaping () -> Void
    ) {
        self.folder = folder
        self.sortField = sortField
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
    
    var isSelectedBinding: Binding<Bool> {
        Binding {
            (
            fileState.currentActiveGroup == .localFolder(folder) &&
            fileState.currentActiveFile == nil
            ) || isBeingDropped
        } set: { val in
            DispatchQueue.main.async {
                if val {
                    fileState.currentActiveGroup = .localFolder(folder)
                    fileState.currentActiveFile = nil
                }
            }
        }
    }
    
    @State private var isBeingDropped = false
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
            isSelected: isSelectedBinding,
            isExpanded: $isExpanded
        ) {
            ForEach(folderChildren) { folder in
                LocalFoldersView(folder: folder, sortField: sortField) {
                    handleSelectedDeletion()
                }
            }
            
            LocalFilesListContentView(folder: folder, sortField: sortField)
        } label: {
            LocalFolderRowView(
                folder: folder,
                isBeingDropped: $isBeingDropped,
                onDelete: onDeleteSelected
            )
        }
        .disclosureGroupIndicatorVisibility(.visible)
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
            LocalFolderRowView(
                folder: folder,
                isBeingDropped: $isBeingDropped,
                onDelete: onDeleteSelected
            )
        } childView: { child in
            LocalFoldersView(folder: child, sortField: sortField) {
                handleSelectedDeletion()
            }
        }
    }
    
    private func handleSelectedDeletion() {
        // switch current folder first if necessary.
        if fileState.currentActiveGroup == .localFolder(folder) {
            guard let index = folderChildren.firstIndex(of: folder) else {
                return
            }
            if index == 0 {
                if folderChildren.count > 1 {
                    fileState.currentActiveGroup = .localFolder(folderChildren[1])
                } else {
                    fileState.currentActiveGroup = nil
                }
            } else {
                fileState.currentActiveGroup = .localFolder(folderChildren[0])
            }
        }
    }
    
}

