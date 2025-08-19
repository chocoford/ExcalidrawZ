//
//  GroupContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/8/25.
//

import SwiftUI

struct GroupMenuProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    struct Triggers {
        var onToggleRename: () -> Void
        var onToogleCreateSubfolder: () -> Void
        var onToggleDelete: () -> Void
    }
    
    var group: Group
    var content: (Triggers) -> AnyView
    
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    
    init<Content: View>(
        group: Group,
        content: @escaping (Triggers) -> Content
    ) {
        self.group = group
        self._childrenGroups = FetchRequest(
            sortDescriptors: [SortDescriptor(\Group.name, order: .forward)],
            predicate: NSPredicate(format: "parent = %@", group),
            animation: .default
        )
        self.content = { AnyView(content($0)) }
    }
    
    @State private var initialNewGroupName: String = ""
    @State private var isDeleteConfirmPresented = false
    @State private var isRenameSheetPresented = false
    @State private var isCreateSubfolderSheetPresented = false

    
    var triggers: Triggers {
        Triggers {
            isRenameSheetPresented.toggle()
        } onToogleCreateSubfolder: {
            isCreateSubfolderSheetPresented.toggle()
        } onToggleDelete: {
            isDeleteConfirmPresented.toggle()
        }
    }
        
    
    var body: some View {
        content(triggers)
            .confirmationDialog(
                group.groupType == .trash
                ? String(localizable: .sidebarGroupRowDeletePermanentlyConfirmTitle)
                : String(localizable: .sidebarGroupRowDeleteConfirmTitle(group.name ?? String(localizable: .generalUntitled))),
                isPresented: $isDeleteConfirmPresented
            ) {
                Button(
                    group.groupType == .trash
                    ? String(localizable: .sidebarGroupRowEmptyTrashButton)
                    : String(localizable: .sidebarGroupRowDeleteButton),
                    role: .destructive
                ) {
                   deleteGroup()
                }
            } message: {
                Text(.localizable(.sidebarGroupRowDeleteMessage))
            }
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenameSheetPresented,
                    name: group.name ?? ""
                ) { newName in
                    fileState.renameGroup(group, newName: newName)
                }
            )
            .sheet(isPresented: $isCreateSubfolderSheetPresented) {
                createSubFolderSheetView()
            }
            .onChange(of: childrenGroups.count) { _ in
                self.initialNewGroupName = getNextGroupName()
            }
            .onAppear {
                self.initialNewGroupName = getNextGroupName()
            }
    }
    
    @MainActor @ViewBuilder
    private func createSubFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: .group
        ) { name in
            Task {
                do {
                    let groupID = try await fileState.createNewGroup(
                        name: name,
                        activate: true,
                        parentGroupID: group.objectID,
                        context: viewContext
                    )
                    fileState.expandToGroup(groupID)
                } catch {
                    alertToast(error)
                }
            }
        }
        .onAppear {
            self.initialNewGroupName = getNextGroupName()
        }
    }
    
    private func getNextGroupName() -> String {
        let name = String(
            localizable: .sidebarGroupListCreateNewGroupNamePlaceholder
        )
        var result = name
        var i = 1
        while childrenGroups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        return result
    }
    
    private func deleteGroup() {
        let groupID = self.group.objectID
        Task.detached {
            // Handle empty trash action.
            do {
                let context = PersistenceController.shared.container.newBackgroundContext()
                try await context.perform {
                    guard case let group as Group = context.object(with: groupID) else { return }
                    try group.delete(context: context)
                }

                await MainActor.run {
                    if case .group = fileState.currentActiveGroup {
                        fileState.currentActiveGroup = nil
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct GroupContextMenuViewModifier: ViewModifier {
    
    var group: Group
    var canExpand: Bool
    
    init(
        group: Group,
        canExpand: Bool,
    ) {
        self.group = group
        self.canExpand = canExpand
    }
    
    func body(content: Content) -> some View {
        GroupMenuProvider(
            group: group
        ) { triggers in
            content
                .contextMenu {
                    GroupMenuItems(
                        group: group,
                        canExpand: canExpand
                    ) {
                        triggers.onToggleRename()
                    } onToogleCreateSubfolder: {
                        triggers.onToogleCreateSubfolder()
                    } onToggleDelete: {
                        triggers.onToggleDelete()
                    }
                }
        }
    }
}

struct GroupMenuItems: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var group: Group
    var canExpand: Bool
    var onToggleRename: () -> Void
    var onToogleCreateSubfolder: () -> Void
    var onToggleDelete: () -> Void
    
    
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    
    init(
        group: Group,
        canExpand: Bool,
        onToggleRename: @escaping () -> Void,
        onToogleCreateSubfolder: @escaping () -> Void,
        onToggleDelete: @escaping () -> Void
    ) {
        self.group = group
        self.canExpand = canExpand
        self.onToggleRename = onToggleRename
        self.onToogleCreateSubfolder = onToogleCreateSubfolder
        self.onToggleDelete = onToggleDelete
        
        self._childrenGroups = FetchRequest(
            sortDescriptors: [SortDescriptor(\Group.name, order: .forward)],
            predicate: NSPredicate(format: "parent = %@", group),
            animation: .default
        )
    }
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelGroups: FetchedResults<Group>
    
    var body: some View {
        if group.groupType != .trash {
            Button {
                onToggleRename()
            } label: {
                if #available(macOS 13.0, *) {
                    Label(
                        .localizable(.sidebarGroupRowContextMenuRename),
                        systemSymbol: .pencilLine
                    )
                } else {
                    // Fallback on earlier versions
                    Label(.localizable(.sidebarGroupRowContextMenuRename), systemSymbol: .pencil)
                }
            }
            
            Button {
                onToogleCreateSubfolder()
            } label: {
                Label(.localizable(.sidebarGroupRowContextMenuAddSubgroup), systemSymbol: .folderBadgePlus)
            }
            
            if canExpand, !childrenGroups.isEmpty {
                Button {
                    self.expandAllSubGroups(group.objectID)
                } label: {
                    Label(.localizable(.sidebarGroupRowContextMenuExpandAll), systemSymbol: .squareFillTextGrid1x2)
                }
            }
            
            if group.groupType != .default {
                Menu {
                    if self.group.parent != nil {
                        Button {
                            performGroupMoveAction(source: self.group.objectID, target: nil)
                        } label: {
                            Text(.localizable(.sidebarGroupRowContextMenuMoveToTopLevel))
                        }
                        
                        Divider()
                    }
                    
                    ForEach(Array(topLevelGroups.filter({$0.groupType != .trash}))) { group in
                        MoveToGroupMenu(
                            destination: group,
                            sourceGroup: self.group,
                            childrenSortKey: \Group.name
                        ) {
                            performGroupMoveAction(source: self.group.objectID, target: $0)
                        }
                    }
                } label: {
                    Label(
                        .localizable(.generalMoveTo),
                        systemSymbol: .trayAndArrowUp
                    )
                }
            }
        }
        
        Button {
            copyEntityURLToClipboard(objectID: group.objectID)
        } label: {
            Label(.localizable(.sidebarGroupRowContextMenuCopyGroupLink), systemSymbol: .link)
        }
        
        if group.groupType != .default {
            Button(role: .destructive) {
                onToggleDelete()
            } label: {
                if group.groupType == .trash {
                    Label(.localizable(.sidebarGroupRowContextMenuEmptyTrash), systemSymbol: .trash)
                } else {
                    Label(
                        .localizable(.sidebarGroupRowContextMenuDelete),
                        systemSymbol: .trash
                    )
                }
            }
        }
    }
    
    private func performGroupMoveAction(source: NSManagedObjectID, target: NSManagedObjectID?) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileState = fileState
        Task.detached {
            do {
                let target: NSManagedObjectID? = try await context.perform {
                    guard let sourceGroup = context.object(with: source) as? Group else {
                        return nil
                    }
                    let targetGroup: Group? = if let target { context.object(with: target) as? Group } else { nil }
                    
                    sourceGroup.parent = targetGroup
                    try context.save()
                    
                    return target
                }
                
                
                await MainActor.run {
                    if let target {
                        fileState.expandToGroup(target)
                    }
                    // IMPORTANT -- viewContext fetch group
                    if let group = viewContext.object(with: source) as? Group {
                        fileState.currentActiveGroup = .group(group)
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func expandAllSubGroups(_ groupID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        NotificationCenter.default.post(name: .shouldExpandGroup, object: groupID)
        Task.detached {
            do {
                try await context.perform {
                    guard let group = context.object(with: groupID) as? Group else { return }
                    let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                    fetchRequest.predicate = NSPredicate(format: "parent = %@", group)
                    let subGroups = try context.fetch(fetchRequest)
                    
                    Task {
                        for subGroup in subGroups {
                            let id = subGroup.objectID
                            await MainActor.run {
                                NotificationCenter.default.post(
                                    name: .shouldExpandGroup,
                                    object: id
                                )
                            }
                            
                            try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                            
                            await expandAllSubGroups(subGroup.objectID)
                        }
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func mergeWithGroup(_ group: Group) {
        guard let files = self.group.files?.allObjects as? [File] else { return }
        fileState.currentActiveGroup = .group(group)
        PersistenceController.shared.container.viewContext.performAndWait {
            for file in files {
                file.group = group
            }
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                print(error)
            }
        }
        let groupID = self.group.objectID
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            guard let selfGroup = bgContext.object(with: groupID) as? Group else { return }
            for file in selfGroup.files?.allObjects as? [File] ?? [] {
                bgContext.delete(file)
            }
            bgContext.delete(selfGroup)
            do {
                try bgContext.save()
            } catch {
                print(error)
            }
        }
    }

}
