//
//  NewGroupButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/13/25.
//

import SwiftUI
import ChocofordUI

private struct FolderTooLargeError: LocalizedError {
    var errorDescription: String? {
        .init(localizable: .sidebarLocalFolderTooLargeAlertDescription)
    }
}

struct NewGroupButton: View {
    @Environment(\.alert) private var alert
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    
    enum GroupType {
        case localFolder
        case group
    }
        
    var groupType: GroupType?
    var parentGroupID: NSManagedObjectID?
    var label: (GroupType) -> AnyView
    
    init(type: GroupType? = nil, parentID: NSManagedObjectID?) {
        self.groupType = type
        self.parentGroupID = parentID
        self.label = { type in
            switch type {
                case .localFolder:
                    AnyView(Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .folderBadgePlus))
                case .group:
                    AnyView(Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .folderBadgePlus))
            }
        }
    }
    
    init<L: View>(
        type: GroupType? = nil,
        parentID: NSManagedObjectID?,
        @ViewBuilder label: @escaping (GroupType) -> L
    ) {
        self.groupType = type
        self.parentGroupID = parentID
        self.label = {
            AnyView(label($0))
        }
    }
    
    var currentGroupType: GroupType? {
        switch fileState.currentActiveGroup {
            case .localFolder:
                return .localFolder
            case .group:
                return .group
            default:
                return nil
        }
    }
    
    @State private var isCreateGroupDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false

    var body: some View {
        content()
            .modifier(
                CreateGroupModifier(
                    isPresented: $isCreateGroupDialogPresented,
                    parentGroupID: parentGroupID,
                )
            )
            .fileImporterWithAlert(
                isPresented: $isCreateLocalFolderDialogPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { urls in
                importLocalFolders(urls: urls)
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        switch groupType ?? currentGroupType {
            case .group:
                Button {
                    isCreateGroupDialogPresented.toggle()
                } label: {
                    label(.group)
                }
            case .localFolder:
                Button {
                    isCreateLocalFolderDialogPresented.toggle()
                } label: {
                    label(.localFolder)
                }
            default:
                EmptyView()
        }
    }
    
    private func importLocalFolders(urls: [URL]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isHiddenKey]
                    ) else {
                        return
                    }
                    
                    var urls: [URL] = []
                    for case let url as URL in enumerator.allObjects {
                        urls.append(url)
                    }
                    
                    // Check the folder is too large (too many subfolders)
                    var count = 0
                    for url in urls {
                        let isHidden = (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if !isHidden && isDirectory {
                            count += 1
                        }
                    }
                    
                    if count > 1000 {
                        await MainActor.run {
                           
                            alert(title: .localizable(.sidebarLocalFolderTooLargeAlertTitle), error: FolderTooLargeError())
                        }
                        return
                    }
                    
                    try await context.perform { [urls] in
                        let localFolder = try LocalFolder(url: url, context: context)
                        context.insert(localFolder)
                        try localFolder.refreshChildren(context: context)
                        // create checkpoints for every file in folder
                        for url in urls {
                            if url.pathExtension == "excalidraw" {
                                let checkpoint = LocalFileCheckpoint(context: context)
                                checkpoint.url = url
                                checkpoint.content = try Data(contentsOf: url)
                                checkpoint.updatedAt = .now
                                context.insert(checkpoint)
                            }
                        }
                        try context.save()
                    }
                    
                    url.stopAccessingSecurityScopedResource()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}
