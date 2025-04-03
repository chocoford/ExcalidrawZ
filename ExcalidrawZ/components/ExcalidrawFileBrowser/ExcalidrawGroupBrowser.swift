//
//  ExcalidrawGroupBrowser.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/19/25.
//

import SwiftUI

struct ExcalidrawGroupBrowser: View {
    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.createdAt, order: .forward),
            SortDescriptor(\.type, order: .forward),
        ],
        predicate: NSPredicate(format: "parent = nil AND type != 'trash'")
    )
    var groups: FetchedResults<Group>
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                let spacing: CGFloat = 4

                // Database Groups
                VStack(alignment: .leading, spacing: spacing) {
                    Text(.localizable(.sidebarGroupListSectionHeaderICloud))
                        .font(.headline)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            GroupsView(group: group)
                        }
                    }
                }
                
                // Local Folders
                VStack(alignment: .leading, spacing: spacing) {
                    Text(.localizable(.sidebarGroupListSectionHeaderLocal))
                        .font(.headline)
                    LocalFoldersListView()
                }
            }
            .padding()
        }
    }
}

#Preview {
    ExcalidrawGroupBrowser()
}
