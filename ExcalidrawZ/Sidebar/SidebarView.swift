//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI

import ChocofordUI

struct SidebarView: View {
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)]
    )
    var groups: FetchedResults<Group>
    
    
    var body: some View {
        HStack(spacing: 0) {
            if appPreference.sidebarMode == .all {
                GroupListView(groups: groups)
                    .frame(minWidth: 150)
                Divider()
            }
            
            ZStack {
                if let currentGroup = fileState.currentGroup {
                    FileListView(groups: groups, currentGroup: currentGroup)
                } else {
                    Text("Select a group")
                        .foregroundStyle(.placeholder)
                }
            }
                .frame(minWidth: 200)
        }
        .border(.top, color: .separatorColor)
    }
}

#Preview {
    SidebarView()
}