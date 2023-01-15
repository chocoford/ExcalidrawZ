//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

struct GroupSidebarView: View {
    @EnvironmentObject var store: AppStore
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)]) private var groups: FetchedResults<Group>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.deletedAt, order: .reverse)],
                  predicate: .init(format: "inTrash == YES")) private var trashFiles: FetchedResults<File>
    
    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""

    private var selectedGroup: Binding<Group?> {
        store.binding(for: \.currentGroup) {
            return .setCurrentGroup($0)
        }
    }

    var body: some View {
        content
            .onAppear(perform: getNextFileName)
            .sheet(isPresented: $showCreateFolderDialog) {
                createGroupDialogView
            }
    }
    
    private var displayedList: [Group] {
        groups
            .filter({ $0.groupType != .trash || $0.groupType == .trash && trashFiles.count > 0 })
            .sorted(by: { $0.groupType < $1.groupType })
    }
    
    @ViewBuilder private var content: some View {
        List(displayedList,
             selection: selectedGroup) { group in
            GroupRowView(group: group)
        }
             .onChange(of: trashFiles.count) { trashFilesCount in
                 if trashFilesCount == 0 && store.state.currentGroup?.groupType == .trash {
                     store.send(.setCurrentGroup(nil))
                 }
             }

        HStack {
            Button {
                showCreateFolderDialog.toggle()
            } label: {
                Label("New folder", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            
            Spacer()
        }
        .padding(4)
    }
    
    @ViewBuilder private var createGroupDialogView: some View {
        VStack(alignment: .leading) {
            Text("New folder")
                .fontWeight(.bold)
            HStack {
                Text("name:")
                TextField("", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Sync to iCloud", isOn: .constant(false))
                .disabled(true)
            
            Divider()
            
            HStack {
                Spacer()
                Button("cancel") {
                    showCreateFolderDialog.toggle()
                }
                Button("create", action: createFolder)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}


extension GroupSidebarView {
    func getNextFileName() {
        let name = "New Folder"
        var result = name
        var i = 1
        while store.state.groups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        newFolderName = result
    }
    
    func createFolder() {
        store.send(.createGroup(newFolderName))
        showCreateFolderDialog.toggle()
    }
}

#if DEBUG
struct GroupSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        GroupSidebarView()
            .environmentObject(AppStore.preview)
    }
}
#endif
