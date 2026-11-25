//
//  LocalFoldersView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI
import SwiftyAlert
import CoreData

import ChocofordUI

struct LocalFoldersView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @Environment(FileState.self) private var fileState
    @Environment(ItemDragState.self) private var sidebarDragState
    @Environment(LocalFolderSidebarExpansionState.self) private var expansion

    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    var showFiles: Bool
    var reorder: SidebarRowReorderAction?
    var onDeleteSelected: () -> Void

    @State private var showFolderNotFoundAlert = false
    @State private var folderNotFoundMessage = ""
        
    @FetchRequest
    private var folderChildren: FetchedResults<LocalFolder>
    
    init(folder: LocalFolder,
         sortField: ExcalidrawFileSortField,
         showFiles: Bool = true,
         reorder: SidebarRowReorderAction? = nil,
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
        self.reorder = reorder
        self.onDeleteSelected = onDeleteSelected
    }
    
    let paddingBase: CGFloat = 14
    
    var isSelectedBinding: Binding<Bool> {
        Binding {
            (
            fileState.currentActiveGroup == .localFolder(folder) &&
            fileState.currentActiveFile == nil
            )
        } set: { selected in
            guard selected else { return }
            fileState.selectLinkedFolder(folder) { error in
                folderNotFoundMessage = error.message
                showFolderNotFoundAlert = true
            }
        }
    }
    
    private var isExpanded: Bool { expansion.isExpanded(folder.objectID) }
    private var isExpandedBinding: Binding<Bool> {
        Binding {
            isExpanded
        } set: {
            expansion.setExpanded($0, for: folder.objectID)
        }
    }
    @State private var refreshTask: Task<Void, Never>?
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, *), folderStructStyle == .disclosureGroup {
                diclsureGroupView()
            } else {
                treeView()
            }
        }
        .reportSidebarFileRevealContents(
            of: folder.sidebarGroupScrollTarget,
            available: folderStructStyle == .tree || isExpanded
        ) { target in
            folderChildren.contains { $0.sidebarGroupScrollTarget == target }
        }
        .animation(.smooth, value: folderStructStyle)
        .alert("Folder Not Found", isPresented: $showFolderNotFoundAlert) {
            LocalFolderMenuProvider(folder: folder) { trigger in
                Button(.localizable(.sidebarLocalFolderRowContextMenuRemoveObservation), role: .destructive) {
                    trigger.onToggleRemoveObservation()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(folderNotFoundMessage)
        }
        .task(id: folder.url?.path ?? folder.objectID.uriRepresentation().absoluteString) {
            await refreshImmediateChildren()
        }
        .onAppear { isVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: .linkedFolderContentsDidChange)) { notification in
            guard isVisible, LinkedFolderIndexState.affects(notification, folderURL: folder.url) else { return }
            refreshTask?.cancel()
            refreshTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await refreshImmediateChildren()
            }
        }
        .onDisappear {
            isVisible = false
            refreshTask?.cancel()
        }
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
    @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: isSelectedBinding,
            isExpanded: isExpandedBinding
        ) {
            VStack(alignment: .leading, spacing: 0) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(folderChildren, id: \.sidebarGroupScrollTarget) { folder in
                        LocalFoldersView(folder: folder, sortField: sortField, showFiles: showFiles) {
                            handleSelectedDeletion()
                        }
                    }
                }
                // The file provider needs to start loading even if the folders
                // above it fill the viewport. Its file rows are lazy as well.
                if showFiles {
                    LocalFilesListContentView(folder: folder, sortField: sortField)
                }
            }
        } label: {
            LocalFolderRowView(
                folder: folder,
                onDelete: onDeleteSelected
            )
            .id(folder.sidebarGroupScrollTarget)
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
                    LocalFolderDropModifier(
                        folder: folder,
                        allowsLocalFolder: { reorder?.contains(.localFolder($0)) != true },
                        dropTarget: { .exact($0) }
                    )
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
                .modifier(LocalFolderDragModifier(folder: folder))
                .modifier(SidebarRowReorderModifier(action: reorder))
        }
        .disclosureGroupIndicatorVisibility(.visible)
        .background {
            if canDropBelowFoler {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
            }
        }
    }
    
    @ViewBuilder
    private func treeView() -> some View {
        TreeStructureView(
            children: folderChildren,
            id: \.sidebarGroupScrollTarget,
            paddingLeading: 6
        ) {
            LocalFolderRowView(
                folder: folder,
                onDelete: onDeleteSelected
            )
            .id(folder.sidebarGroupScrollTarget)
            .modifier(LocalFolderDragModifier(folder: folder))
            .modifier(
                LocalFolderContextMenuModifier(
                    folder: folder,
                    canExpand: true,
                )
            )
            .modifier(SidebarRowReorderModifier(action: reorder))
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

    private func refreshImmediateChildren() async {
        do {
            try await LocalFolder.refreshImmediateChildren(of: folder.objectID)
        } catch is CancellationError {
            return
        } catch {
            alertToast(error)
        }
    }
    
}
