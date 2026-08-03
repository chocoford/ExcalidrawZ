//
//  NewGroupButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/13/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct NewGroupButton: View {
    @Environment(\.alert) private var alert
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    enum GroupType {
        case localFolder
        case group
        case cloudStorageFolder
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
                case .cloudStorageFolder:
                    AnyView(Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .folderBadgePlus))
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
            case .cloudStorageFolder:
                return .cloudStorageFolder
            default:
                return nil
        }
    }
    
    @State private var isCreateGroupDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false
    @State private var isCreateCloudFolderDialogPresented = false
    @State private var isCreatingCloudFolder = false
    @State private var newCloudFolderName = ""

    var body: some View {
        content()
            .modifier(
                CreateGroupModifier(
                    isPresented: $isCreateGroupDialogPresented,
                    parentGroupID: parentGroupID,
                )
            )
            .modifier(
                CreateFolderModifier(
                    isPresented: $isCreateLocalFolderDialogPresented,
                    parentFolderID: parentGroupID
                )
            )
            .sheet(isPresented: $isCreateCloudFolderDialogPresented) {
                cloudFolderSheet
            }
    }
    
    @ViewBuilder
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
            case .cloudStorageFolder:
                Button {
                    guard !isCreatingCloudFolder else { return }
                    guard case .cloudStorageFolder(let folder) = fileState.currentActiveGroup else {
                        return
                    }
                    newCloudFolderName = CloudStorageDocumentStore.shared.availableFolderName(
                        in: folder
                    )
                    isCreateCloudFolderDialogPresented = true
                } label: {
                    ZStack {
                        label(.cloudStorageFolder)
                            .opacity(isCreatingCloudFolder ? 0 : 1)

                        if isCreatingCloudFolder {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isCreatingCloudFolder)
            default:
                EmptyView()
        }
    }

    @ViewBuilder
    private var cloudFolderSheet: some View {
        CreateGroupSheetView(
            name: $newCloudFolderName,
            createType: .localFolder
        ) { name in
            guard !isCreatingCloudFolder else { return }
            guard case .cloudStorageFolder(let parent) = fileState.currentActiveGroup else {
                return
            }
            isCreatingCloudFolder = true
            Task {
                defer { isCreatingCloudFolder = false }
                do {
                    let folder = try await CloudStorageDocumentStore.shared.createFolder(
                        named: name,
                        in: parent
                    )
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(folder))
                } catch {
                    alertToast(error)
                }
            }
        }
        .controlSize(.large)
#if os(macOS)
        .frame(width: 400, height: 140)
#endif
    }

}
