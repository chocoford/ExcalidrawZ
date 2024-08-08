//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import ChocofordEssentials


struct GroupListView: View {
    @EnvironmentObject var fileState: FileState
    
    var groups: FetchedResults<Group>
    
    init(groups: FetchedResults<Group>) {
        self.groups = groups
    }
    
    var displayedGroups: [Group] {
        groups.filter {
            $0.groupType != .trash || ($0.groupType == .trash && self.trashedFilesCount > 0)
        }
    }
    
    var trashedFilesCount: Int { 0 }
    
    
    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""
    
    
    var body: some View {
        content
            .onAppear(perform: getNextFileName)
            .sheet(isPresented: $showCreateFolderDialog) {
                CreateGroupSheetView(initialName: newFolderName) { name in
                    
                }
            }
    }
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedGroups) { group in
                        GroupRowView(group: group)
                            .padding(.horizontal, 8)
                    }
                }
                .onChange(of: trashedFilesCount) { count in
                    if count == 0 && fileState.currentGroup?.groupType == .trash {
//                        viewStore.send(.setCurrentGroup(group: nil))
                    }
                }
                .padding(.vertical, 12)
                .onChange(of: displayedGroups) { newValue in
                    if fileState.currentGroup == nil {
//                        self.store.send(.setCurrentGroupToFirst)
                    }
                }
                .watchImmediately(of: fileState.currentGroup) { newValue in
                    if newValue == nil {
//                        self.store.send(.setCurrentGroupToFirst)
                    }
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
    }
}


extension GroupListView {
    func getNextFileName() {
//        self.store.withState { state in
//            let name = "New Folder"
//            var result = name
//            var i = 1
//            while state.state.groupRows.first(where: {$0.group.name == result}) != nil {
//                result = "\(name) \(i)"
//                i += 1
//            }
//            newFolderName = result
//        }
    }
    
    func createFolder() {
//        self.store.send(.createGroup(name: newFolderName))
        showCreateFolderDialog = false
    }
}

struct CreateGroupSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    var initialName: String
    var onCreate: (_ name: String) -> Void
    
    @State private var name: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("New folder")
                .fontWeight(.bold)
            HStack {
                Text("name:")
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !name.isEmpty {
                            onCreate(name)
                            dismiss()
                        }
                    }
            }
            Toggle("Sync to iCloud", isOn: .constant(false))
                .disabled(true)
            
            Divider()
            
            HStack {
                Spacer()
                Button("cancel") { dismiss() }
                Button("create") {
                    onCreate(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onChange(of: self.initialName) { newValue in self.name = newValue }
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
 
