//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

import ChocofordEssentials
import ChocofordUI

struct GroupListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil")
    )
    var groups: FetchedResults<Group>
    
    init() { }
    
    var displayedGroups: [Group] {
        groups
            .filter {
                $0.groupType != .trash || ($0.groupType == .trash && self.trashedFilesCount > 0)
            }
            .sorted { a, b in
                a.groupType == .default && b.groupType != .default ||
                a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast  ||
                a.groupType != .trash && b.groupType == .trash
            }
    }
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "inTrash == YES")
    )
    private var trashedFiles: FetchedResults<File>
    
    var trashedFilesCount: Int { trashedFiles.count }
    
    @State private var isCreateICloudFolderDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false
    
    @State private var createGroupType: CreateGroupSheetView.CreateGroupType = .group
    @State private var isCreateGroupDialogPresented = false
    
    var body: some View {
        content
            .sheet(isPresented: $isCreateGroupDialogPresented) {
                if containerHorizontalSizeClass == .compact {
                    createFolderSheetView()
#if os(iOS)
                        .presentationDetents([.height(140)])
                        .presentationDragIndicator(.visible)
#endif
                } else if #available(iOS 18.0, macOS 13.0, *) {
                    createFolderSheetView()
                        .scrollDisabled(true)
                        .frame(width: 400, height: 140)
#if os(iOS)
                        .presentationSizing(.fitted)
#endif
                } else {
                    createFolderSheetView()
                }
            }
            .onAppear {
                if fileState.currentGroup == nil {
                    fileState.currentGroup = displayedGroups.first
                }
                initialNewGroupName = getNextGroupName()
            }
    }
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    let spacing: CGFloat = 4
                    // Temporary
                    if !fileState.temporaryFiles.isEmpty {
                        VStack(alignment: .leading, spacing: spacing) {
                            TemporaryGroupRowView()
                        }
                    }
                    // iCloud
                    VStack(alignment: .leading, spacing: spacing) {
                        databaseGroupsList()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    isCreateDialogPresented: Binding {
                                        isCreateGroupDialogPresented && createGroupType == .group
                                    } set: {
                                        if $0 {
                                            isCreateGroupDialogPresented = true
                                            createGroupType = .group
                                        } else {
                                            isCreateGroupDialogPresented = false
                                        }
                                    },
                                    title: "iCloud"
                                )
                            )
                    }
                    
                    // Local
                    VStack(alignment: .leading, spacing: spacing) {
                        LocalFoldersListView()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    isCreateDialogPresented: $isCreateLocalFolderDialogPresented,
                                    title: "Local"
                                )
                            )
                            .fileImporterWithAlert(
                                isPresented: $isCreateLocalFolderDialogPresented,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: true
                            ) { urls in
                                try importLocalFolders(urls: urls)
                            }
                    }
                }
                .padding(8)
            }
            .clipped()
            
//            HStack {
//                Button {
//                    isCreateGroupDialogPresented.toggle()
//                    createGroupType = .group
//                } label: {
//                    Label(.localizable(.sidebarGroupListNewFolder), systemSymbol: .plusCircle)
//                }
//                .buttonStyle(.borderless)
//                
//                Spacer()
//            }
//            .padding(4)
        }
    }
    
    @MainActor @ViewBuilder
    private func databaseGroupsList() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(displayedGroups) { group in
                GroupsView(group: group, groups: groups)
            }
        }
        .onChange(of: trashedFilesCount) { count in
            if count == 0 && fileState.currentGroup?.groupType == .trash {
                fileState.currentGroup = displayedGroups.first
            }
        }
        .onChange(of: displayedGroups) { newValue in
            if fileState.currentGroup == nil {
                fileState.currentGroup = displayedGroups.first
            } else if !displayedGroups.contains(where: {$0 == fileState.currentGroup}) {
                fileState.currentGroup = displayedGroups.first
            }
            initialNewGroupName = getNextGroupName()
        }
        .watchImmediately(of: fileState.currentGroup) { newValue in
            if newValue == nil && fileState.currentLocalFolder == nil && !fileState.isTemporaryGroupSelected {
                fileState.currentGroup = displayedGroups.first
            }
        }
    }
    
    @State private var initialNewGroupName: String = ""
    
    @MainActor @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: createGroupType
        ) { name in
            Task {
                do {
                    try await fileState.createNewGroup(
                        name: name,
                        activate: true,
                        context: managedObjectContext
                    )
                } catch {
                    alertToast(error)
                }
            }
        }
    }
    
    func getNextGroupName() -> String {
        let name = String(localizable: .sidebarGroupListCreateNewGroupNamePlaceholder)
        var result = name
        var i = 1
        while groups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        return result
    }
    
    private func importLocalFolders(urls: [URL]) throws {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                continue
            }
             
            try managedObjectContext.performAndWait {
                let localFolder = try LocalFolder(url: url, context: managedObjectContext)
                managedObjectContext.insert(localFolder)
                try managedObjectContext.save()
            }
            
            url.stopAccessingSecurityScopedResource()
        }
    }
}

fileprivate struct ContentHeaderCreateButtonHoverModifier: ViewModifier {
    
    @Binding var isCreateDialogPresented: Bool
    var title: LocalizedStringKey
    
    init(
        isCreateDialogPresented: Binding<Bool>,
        title: LocalizedStringKey
    ) {
        self._isCreateDialogPresented = isCreateDialogPresented
        self.title = title
    }
    
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        Section {
            content
        } header: {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovered {
                    Button {
                        isCreateDialogPresented.toggle()
                    } label: {
                        Label(.localizable(.sidebarGroupListNewFolder), systemSymbol: .plusCircleFill)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.callout.bold())
            .animation(.smooth, value: isHovered)
        }
        .onHover {
            isHovered = $0
        }
    }
}



#if DEBUG


//struct GroupSidebarView_Previews: PreviewProvider {
//    static var previews: some View {
//        GroupListView(
//            store: .init(
//                initialState: .init(
//                    groups: [Group.preview],
//                    state: .init()
//                ),
//                reducer: {
//                    GroupStore()
//                }
//            )
//        )
//    }
//}
#endif
 
