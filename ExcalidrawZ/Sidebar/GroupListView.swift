//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import ChocofordEssentials


struct GroupListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var groups: FetchedResults<Group>
    
    init(groups: FetchedResults<Group>) {
        self.groups = groups
    }
    
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
    
    @State private var showCreateFolderDialog = false
    
    
    var body: some View {
        content
            .sheet(isPresented: $showCreateFolderDialog) {
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
            .onChange(of: displayedGroups) { newValue in
                if fileState.currentGroup == nil {
                    fileState.currentGroup = newValue.first
                } else if newValue.contains(where: {$0.id == fileState.currentGroup?.id}) == false {
                    fileState.currentGroup = newValue.first
                }
            }
            .onAppear {
                if fileState.currentGroup == nil {
                    fileState.currentGroup = displayedGroups.first
                }
            }
    }
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedGroups) { group in
                        GroupRowView(group: group, groups: displayedGroups)
                            .padding(.horizontal, 8)
                    }
                }
                .onChange(of: trashedFilesCount) { count in
                    if count == 0 && fileState.currentGroup?.groupType == .trash {
                        fileState.currentGroup = displayedGroups.first
                    }
                }
                .padding(.vertical, 12)
                .onChange(of: displayedGroups) { newValue in
                    if fileState.currentGroup == nil {
                        fileState.currentGroup = displayedGroups.first
                    } else if !displayedGroups.contains(where: {$0 == fileState.currentGroup}) {
                        fileState.currentGroup = displayedGroups.first
                    }
                }
                .watchImmediately(of: fileState.currentGroup) { newValue in
                    if newValue == nil {
                        fileState.currentGroup = displayedGroups.first
                    }
                }
            }
            .clipped()
            HStack {
                Button {
                    showCreateFolderDialog.toggle()
                } label: {
                    Label(.localizable(.sidebarGroupListNewFolder), systemSymbol: .plusCircle)
                }
                .buttonStyle(.borderless)
                
                Spacer()
            }
            .padding(4)
        }
    }
    
    @MainActor @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(groups: groups) { name in
            Task {
                do {
                    try await fileState.createNewGroup(name: name, activate: true, context: managedObjectContext)
                } catch {
                    alertToast(error)
                }
            }
        }
    }
}

struct CreateGroupSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    var groups: FetchedResults<Group>
    
    var onCreate: (_ name: String) -> Void
    
    @State private var name: String = ""
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text(.localizable(.sidebarGroupListCreateGroupName))
                    TextField("", text: $name)
                        .submitLabel(.done)
    #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !name.isEmpty {
                                onCreate(name)
                                dismiss()
                            }
                        }
    #endif
                }
            } header: {
                Text(.localizable(.sidebarGroupListCreateTitle))
                    .fontWeight(.bold)
            } footer: {
                HStack {
                    Spacer()
                    Button(.localizable(.sidebarGroupListCreateButtonCancel)) { dismiss() }
                    Button(.localizable(.sidebarGroupListCreateButtonCreate)) {
                        onCreate(name)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
                }
            }
//#if os(macOS)
//            Divider()
//#endif
            
        }
        .labelsHidden()
#if os(macOS)
        .padding()
#endif
        .onAppear {
            self.name = getNextFileName()
        }
    }
    
    func getNextFileName() -> String {
        let name = String(localizable: .sidebarGroupListCreateNewGroupNamePlaceholder)
        var result = name
        var i = 1
        while groups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        return result
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
 
