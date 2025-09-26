//
//  NewGroupButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/13/25.
//

import SwiftUI
import ChocofordUI



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
            .modifier(
                CreateFolderModifier(
                    isPresented: $isCreateLocalFolderDialogPresented,
                    parentFolderID: parentGroupID
                )
            )
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
    

}
