//
//  GroupSidebarView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

struct GroupSidebarView: View {
    @EnvironmentObject var store: AppStore
    
    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""

    private var selectedGroup: Binding<GroupInfo> {
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
    
    
    @ViewBuilder private var content: some View {
        List(store.state.assetGroups, selection: selectedGroup) { group in
            NavigationLink(group.name, value: group)
        }
        .navigationTitle("Folder")

        HStack {
            Button {
                showCreateFolderDialog.toggle()
            } label: {
                Label("New folder", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            
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
        while store.state.assetGroups.first(where: {$0.name == name}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        newFolderName = result
    }
    
    func createFolder() {
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
