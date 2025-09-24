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

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: ItemDragState
    
    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    var showFiles: Bool
    var onDeleteSelected: () -> Void
        
    @FetchRequest
    private var folderChildren: FetchedResults<LocalFolder>
    
    init(folder: LocalFolder,
         sortField: ExcalidrawFileSortField,
         showFiles: Bool = true,
         onDeleteSelected: @escaping () -> Void
    ) {
        self.folder = folder
        self.sortField = sortField
        self._folderChildren = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \LocalFolder.rank, ascending: true),
                NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true),
            ],
            predicate: NSPredicate(format: "parent = %@", folder),
            animation: .default
        )
        self.showFiles = showFiles
        self.onDeleteSelected = onDeleteSelected
    }
    
    let paddingBase: CGFloat = 14
    
    var isSelectedBinding: Binding<Bool> {
        Binding {
            (
            fileState.currentActiveGroup == .localFolder(folder) &&
            fileState.currentActiveFile == nil
            )
        } set: { val in
            DispatchQueue.main.async {
                if val {
                    fileState.currentActiveGroup = .localFolder(folder)
                    fileState.currentActiveFile = nil
                }
            }
        }
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
    
    var dragItemURL: URL? {
        if case .localFile(let url) = sidebarDragState.currentDragItem {
           url
       } else if case .localFolder(let folderID) = sidebarDragState.currentDragItem {
           (viewContext.object(with: folderID) as? LocalFolder)?.url
       } else {
           nil
       }
    }
    
    var canDrop: Bool {
        if let dragItemURL,
           dragItemURL.deletingLastPathComponent() != folder.url,
           folder.url?.filePath.hasPrefix(dragItemURL.filePath) == false {
            return true
        } else if case .file = sidebarDragState.currentDragItem {
            return true
        } else if case .group = sidebarDragState.currentDragItem {
            return true
        } else if case .collaborationFile = sidebarDragState.currentDragItem {
            return true
        } else if case .temporaryFile = sidebarDragState.currentDragItem {
            return true
        }
        return false
    }
    
    var canDropToFolder: Bool {
        sidebarDragState.currentDropGroupTarget == .exact(.localFolder(folder.objectID)) && canDrop
    }
    
    var canDropBelowFoler: Bool {
        sidebarDragState.currentDropGroupTarget == .below(.localFolder(folder.objectID)) && canDrop
    }
    
    
    @available(macOS 13.0, *)
    @MainActor @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: isSelectedBinding,
            isExpanded: $isExpanded
        ) {
            ForEach(folderChildren) { folder in
                LocalFoldersView(folder: folder, sortField: sortField, showFiles: showFiles) {
                    handleSelectedDeletion()
                }
            }
            if showFiles {
                LocalFilesListContentView(folder: folder, sortField: sortField)
            }
        } label: {
            LocalFolderRowView(
                folder: folder,
                onDelete: onDeleteSelected
            )
            .modifier(LocalFolderDragModifier(folder: folder))
        }
        .extraLabelStyle { content in
            content
                .modifier(
                    LocalFolderContextMenuModifier(
                        folder: folder,
                        canExpand: true,
                    )
                )
                .modifier(
                    LocalFolderDropModifier(folder: folder) { .exact($0) }
                )
                .foregroundStyle(
                    canDropToFolder || canDropBelowFoler
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(HierarchicalShapeStyle.primary)
                )
                .background {
                    if canDropToFolder || canDropBelowFoler && !isExpanded {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    } else if canDropBelowFoler && isExpanded {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 12,
                                bottomLeading: 0,
                                bottomTrailing: 0,
                                topTrailing: 12
                            )
                        )
                        .fill(Color.accentColor)
                    }
                }
        }
        .disclosureGroupIndicatorVisibility(.visible)
        .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
            guard let targetGroupID = notification.object as? NSManagedObjectID,
                  targetGroupID == self.folder.objectID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.isExpanded = true
            }
        }
        .background {
            if canDropBelowFoler {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
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
                onDelete: onDeleteSelected
            )
            .modifier(LocalFolderDragModifier(folder: folder))
            .modifier(
                LocalFolderContextMenuModifier(
                    folder: folder,
                    canExpand: true,
                )
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

