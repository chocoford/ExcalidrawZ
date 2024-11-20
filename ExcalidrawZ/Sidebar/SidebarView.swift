//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI
import CoreData

import ChocofordUI

struct SidebarView: View {
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)]
    )
    var groups: FetchedResults<Group>
    
    
    var body: some View {
        twoColumnSidebar()
            .onReceive(
                NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            ) { notification in
                if let userInfo = notification.userInfo {
                    if let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event {
                        print("NSPersistentCloudKitContainer.eventChangedNotification: \(event.type), succeeded: \(event.succeeded)")
                        if event.type == .import, event.succeeded {
                            mergeDefaultGroupAndTrashIfNeeded()
                        }
                    }
                }
            }
    }
    
    
    @MainActor @ViewBuilder
    private func twoColumnSidebar() -> some View {
        HStack(spacing: 0) {
            if appPreference.sidebarMode == .all {
                GroupListView(groups: groups)
#if os(macOS)
                    .frame(minWidth: 150)
#endif
                Divider()
                    .ignoresSafeArea(edges: .bottom)
            }
            
            ZStack {
                if let currentGroup = fileState.currentGroup {
                    FileListView(
                        currentGroupID: currentGroup.id,
                        groupType: currentGroup.groupType
                    )
                } else {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        Text(.localizable(.sidebarFilesPlaceholder))
                            .foregroundStyle(.placeholder)
                    } else {
                        Text(.localizable(.sidebarFilesPlaceholder))
                            .foregroundStyle(.secondary)
                    }
                }
            }
#if os(macOS)
            .frame(minWidth: 200)
#endif
        }
        .border(.top, color: .separatorColor)
        .background {
            List(selection: $fileState.currentFile) {}
        }
    }
    
    @MainActor @ViewBuilder
    private func singleColumnSidebar() -> some View {
        List(selection: $fileState.currentFile) {
            
        }
    }
    
    private func mergeDefaultGroupAndTrashIfNeeded() {
        let container = PersistenceController.shared.container
        Task {
            do {
                let context = container.viewContext//.newBackgroundContext()
                try await context.perform {
                    let groups = try context.fetch(NSFetchRequest<Group>(entityName: "Group"))
                    
                    let defaultGroups = groups.filter({$0.groupType == .default})
                    
                    // Merge default groups
                    if defaultGroups.count > 1 {
                        let theEearlisetGroup = defaultGroups.sorted(by: {
                            ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
                        }).first!
                        
                        try defaultGroups.forEach { group in
                            if group != theEearlisetGroup {
                                let defaultGroupFilesfetchRequest = NSFetchRequest<File>(entityName: "File")
                                defaultGroupFilesfetchRequest.predicate = NSPredicate(format: "group == %@", group)
                                let defaultGroupFiles = try context.fetch(defaultGroupFilesfetchRequest)
                                defaultGroupFiles.forEach { file in
                                    file.group = theEearlisetGroup
                                }
                                context.delete(group)
                            }
                        }
                        
                        DispatchQueue.main.async {
                            fileState.currentGroup = theEearlisetGroup
                        }
                    }
                    
                    let trashGroups = groups.filter({$0.groupType == .trash})
                    trashGroups.dropFirst().forEach { trash in
                        context.delete(trash)
                    }
                }
                try context.save()
            } catch {
                alertToast(error)
            }
        }
    }
}

#Preview {
    SidebarView()
}
