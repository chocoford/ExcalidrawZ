//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI
import CoreData

struct GroupInfo: Equatable {
    private(set) var groupEntity: Group
    
    // group info
    private(set) var id: UUID
    private(set) var name: String
    private(set) var type: Group.GroupType
    private(set) var createdAt: Date
    private(set) var icon: String?
//    private(set) var files: [File]
    
    init(_ groupEntity: Group) {
        self.groupEntity = groupEntity
        self.id = groupEntity.id ?? UUID()
        self.name = groupEntity.name ?? String(localizable: .generalUntitled)
        self.type = groupEntity.groupType
        self.createdAt = groupEntity.createdAt ?? .distantPast
        self.icon = groupEntity.icon
        
//        self.files = groupEntity.files?.allObjects
    }
    
    public mutating func rename(_ newName: String) {
        self.name = newName
        self.groupEntity.name = newName
    }
    
    public func delete() {
//        self.groupEntity
    }
}

struct GroupRowView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelGroups: FetchedResults<Group>
    
    var group: Group
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    @Binding var isExpanded: Bool
    
    /// Tap to select is move to parent view -- GroupsView
    /// in system above macOS 13.0.
    init(
        group: Group,
        isExpanded: Binding<Bool>
    ) {
        self.group = group
        self._childrenGroups = FetchRequest(
            sortDescriptors: [SortDescriptor(\Group.name, order: .forward)],
            predicate: NSPredicate(format: "parent = %@", group),
            animation: .default
        )
        self._isExpanded = isExpanded
    }

    @State private var isDeleteConfirmPresented = false
    @State private var isRenameSheetPresented = false
    @State private var isCreateSubfolderSheetPresented = false

    var isSelected: Bool { fileState.currentGroup == group }

    var body: some View {
        if group.groupType != .trash {
            if #available(macOS 13.0, *) {
                content
                    .dropDestination(for: FileLocalizable.self) { fileInfos, location in
                        guard let _ = fileInfos.first else { return false }
                        return true
                    }
            } else {
                content
            }
        } else {
            content
        }
    }

    @MainActor @ViewBuilder
    private var content: some View {
        groupRowView()
            .contextMenu { contextMenuView }
            .confirmationDialog(
                group.groupType == .trash ? LocalizedStringKey.localizable(.sidebarGroupRowDeletePermanentlyConfirmTitle) : LocalizedStringKey.localizable(.sidebarGroupRowDeleteConfirmTitle(group.name ?? String(localizable: .generalUntitled))),
                isPresented: $isDeleteConfirmPresented
            ) {
                Button(
                    group.groupType == .trash ? LocalizedStringKey.localizable(.sidebarGroupRowEmptyTrashButton) : LocalizedStringKey.localizable(.sidebarGroupRowDeleteButton),
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
                    name: group.name ?? "") { newName in
                        fileState.renameGroup(group, newName: newName)
                    }
            )
            .sheet(isPresented: $isCreateSubfolderSheetPresented) {
                createSubFolderSheetView()
            }
    }

    @MainActor @ViewBuilder
    private func groupRowView() -> some View {
        if folderStructStyle == .disclosureGroup {
            HStack {
                Label {
                    Text(group.name ?? String(localizable: .generalUntitled)).lineLimit(1)
                } icon: {
                    groupIcon
                }
                Spacer()
            }
            .contentShape(Rectangle())
        } else {
            Button {
                fileState.currentGroup = group
            } label: {
                HStack {
                    Label {
                        Text(group.name ?? String(localizable: .generalUntitled)).lineLimit(1)
                    } icon: {
                        groupIcon
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ListButtonStyle(selected: isSelected))
        }
    }
    
    @MainActor @ViewBuilder
    private var groupIcon: some View {
        switch group.groupType {
            case .`default`:
                Image(systemSymbol: .folder)
            case .trash:
                Image(systemSymbol: .trash)
            case .normal:
                Image(systemSymbol: .init(rawValue: group.icon ?? "folder"))
        }
    }
    
    // MARK: - Context Menu
    @MainActor @ViewBuilder
    private var contextMenuView: some View {
        ZStack {
            if group.groupType != .trash {
                Button {
                    isRenameSheetPresented.toggle()
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
            }
            
            if group.groupType != .trash {
                Button {
                    isCreateSubfolderSheetPresented.toggle()
                } label: {
                    Label(.localizable(.sidebarGroupRowContextMenuAddSubgroup), systemSymbol: .folderBadgePlus)
                }
                
                if folderStructStyle == .disclosureGroup, !childrenGroups.isEmpty {
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
                            .localizable(.sidebarFileRowContextMenuMoveTo),
                            systemSymbol: .trayAndArrowUp
                        )
                    }
                }
            }
            
            if group.groupType != .default {
                Button(role: .destructive) {
                    isDeleteConfirmPresented.toggle()
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
        .labelStyle(.titleAndIcon)
    }
    
    private func mergeWithGroup(_ group: Group) {
        guard let files = self.group.files?.allObjects as? [File] else { return }
        fileState.currentGroup = group
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
    
    @State private var initialNewGroupName: String = ""
    
    @MainActor @ViewBuilder
    private func createSubFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: .group
        ) { name in
            Task {
                do {
                    try await fileState.createNewGroup(
                        name: name,
                        activate: true,
                        parentGroupID: group.objectID,
                        context: viewContext
                    )
                    withAnimation(.smooth(duration: 0.2)) {
                        isExpanded = true
                    }
                } catch {
                    alertToast(error)
                }
            }
        }
        .onAppear {
            self.initialNewGroupName = getNextGroupName()
        }
    }
    
    func getNextGroupName() -> String {
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
    
    private func performGroupMoveAction(source: NSManagedObjectID, target: NSManagedObjectID?) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileState = fileState
        Task.detached {
            do {
                try await context.perform {
                    guard let sourceGroup = context.object(with: source) as? Group else {
                        return
                    }
                    let targetGroup: Group? = if let target { context.object(with: target) as? Group } else { nil }
                    
                    sourceGroup.parent = targetGroup
                    try context.save()
                    
                    if let target {
                        fileState.expandToGroup(target)
                    }
                }
                await MainActor.run {
                    // IMPORTANT -- viewContext fetch group
                    fileState.currentGroup = viewContext.object(with: source) as? Group
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
                            await MainActor.run {
                                NotificationCenter.default.post(name: .shouldExpandGroup, object: subGroup.objectID)
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
    
    private func deleteGroup() {
        let groupID = self.group.objectID
        Task.detached {
            // Handle empty trash action.
            do {
                let context = PersistenceController.shared.container.newBackgroundContext()
                try await context.perform {
                    guard case let group as Group = context.object(with: groupID) else { return }

                    if group.groupType == .trash {
                        let files = try PersistenceController.shared.listTrashedFiles(context: context)
                        for file in files {
                            // Also delete checkpoints
                            let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                            checkpointsFetchRequest.predicate = NSPredicate(format: "file = %@", file)
                            let fileCheckpoints = try context.fetch(checkpointsFetchRequest)
                            let objectIDsToBeDeleted = fileCheckpoints.map{$0.objectID}
                            if !objectIDsToBeDeleted.isEmpty {
                                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDsToBeDeleted)
                                try context.executeAndMergeChanges(using: batchDeleteRequest)
                            }
                            context.delete(file)
                        }
                    } else {
                        guard let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context) else {
                            throw AppError.fileError(.notFound)
                        }
                        
                        // get all subgroups' files
                        var allFiles: [File] = []
                        var allGroups: [Group] = [group]
                        var groupIndex = -1
                        var parentGroup = group
                        while groupIndex < allGroups.count {
                            if groupIndex >= 0 {
                                parentGroup = allGroups[groupIndex]
                            }
                            
                            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                            fetchRequest.predicate = NSPredicate(format: "parent = %@", parentGroup)
                            let groups = try context.fetch(fetchRequest)
                            allGroups.append(contentsOf: groups)
                            
                            let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
                            fileFetchRequest.predicate = NSPredicate(format: "group = %@", parentGroup)
                            let files = try context.fetch(fileFetchRequest)
                            allFiles.append(contentsOf: files)
                            
                            groupIndex += 1
                        }
                        
                        
                        for file in allFiles {
                            file.inTrash = true
                            file.deletedAt = .now
                            file.group = defaultGroup
                        }
                        
                        for group in allGroups {
                            context.delete(group)
                        }
                        // Issue: Could not merge changes...
                        // let batchDeletion = NSBatchDeleteRequest(objectIDs: allGroups.map{$0.objectID})
                        // try context.executeAndMergeChanges(using: batchDeletion)
                    }
                    try context.save()
                }

                await MainActor.run {
                    if group == fileState.currentGroup {
                        fileState.currentGroup = nil
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}







#if DEBUG
//struct GroupRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack(spacing: 20) {
//            GroupRowView(
//                store: .init(initialState: .init(group: .preview, isSelected: false)) {
//                    GroupRowStore()
//                }
//            )
//            
//            GroupRowView(
//                store: .init(initialState: .init(group: .preview, isSelected: true)) {
//                    GroupRowStore()
//                }
//            )
//        }
//        .padding()
//    }
//}
#endif
