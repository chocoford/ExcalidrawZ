//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI

import ChocofordUI

struct SidebarView: View {
    @Environment(AppPreference.self) var appPreference
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    var groups: FetchedResults<Group>
    
    
    var body: some View {
        HStack(spacing: 0) {
            if appPreference.sidebarMode == .all {
                GroupListView(groups: groups)
                    .frame(minWidth: 150)
                Divider()
            }
            
            FileListView(groups: groups)
                .frame(minWidth: 200)
        }
        .border(.top, color: .separatorColor)
    }
}

#Preview {
    SidebarView()
}
