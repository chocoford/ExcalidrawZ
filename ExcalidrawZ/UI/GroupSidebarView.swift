//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import ChocofordEssentials
import ComposableArchitecture

struct GroupStore: ReducerProtocol {
    struct State: Equatable {
        var groups: IdentifiedArrayOf<GroupRowStore.State>
        var trashedFilesCount: Int
        
        init(
            groups: IdentifiedArrayOf<GroupRowStore.State> = .init(),
            trashedFilesCount: Int = 0
        ) {
            self.groups = groups
            self.trashedFilesCount = trashedFilesCount
        }
        
        /// groups that not deleted.
        var availableGroups: IdentifiedArrayOf<GroupRowStore.State> {
            self.groups.filter {
                $0.group.groupType != .trash || $0.group.groupType == .trash
            } //  && trashFiles.count > 0
        }
        
        var currentGroup: Group? {
            get { groups.first(where: {$0.isSelected})?.group }
            set {
                for group in groups {
                    if group.id == newValue?.id {
                        groups[id: group.id]?.isSelected = true
                    } else {
                        groups[id: group.id]?.isSelected = false
                    }
                }
            }
            
        }
    }
    
    enum Action: Equatable {
        case group(id: GroupRowStore.State.ID, action: GroupRowStore.Action)

        case createGroup(name: String)
        
        case fetchGroups
        case setGroups(groups: [Group])
        case setCurrentGroup(group: Group?)
        case setCurrentGroupToFirst
        
        case fetchTrashedFiles
        case setTrashedFilesCount(Int)
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case didChooseGroup(Group?)
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        @Dependency(\.coreData) var coreData
        
        Reduce { state, action in
            switch action {
                case .createGroup(let name):
                    do {
                        let group = try coreData.provider.createGroup(name: name)
                        coreData.provider.save()
                        return .send(.setCurrentGroup(group: group))
                    } catch {
                        return .none
                    }
                    
                case .fetchGroups:
                    do {
                        let groups = try coreData.provider.listGroups()
                        return .send(.setGroups(groups: groups))
                    } catch {
                        dump(error)
                        return .none
                    }
                    
                case .setGroups(let groups):
                    state.groups = IdentifiedArray(
                        uniqueElements: groups.map {
                            GroupRowStore.State(group: $0, isSelected: false)
                        }
                    )
                    return .none
                    
                case .setCurrentGroup(let group):
                    state.currentGroup = group
                    return .send(.delegate(.didChooseGroup(group)))
                    
                case .setCurrentGroupToFirst:
                    return .send(.setCurrentGroup(group: state.groups.first?.group))
                    
                case .group(let id , .delegate(let action)):
                    switch action {
                        case .didSetAsCurrentGroup:
                            return .send(.setCurrentGroup(group: state.groups[id: id]?.group))
                    }
                    
                case .group:
                    return .none
                    
                case .fetchTrashedFiles:
                    let trashedFilesCount = (try? coreData.provider.listTrashedFiles())?.count ?? 0
                    return .send(.setTrashedFilesCount(trashedFilesCount))
                    
                case .setTrashedFilesCount(let count):
                    state.trashedFilesCount = count
                    return .none
                    
                case .delegate:
                    return .none
            }
        }
        .forEach(\.groups, action: /Action.group) {
            GroupRowStore()
        }
    }
}

struct GroupSidebarView: View {
    let store: StoreOf<GroupStore>
    
    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        content
            .onAppear(perform: getNextFileName)
            .sheet(isPresented: $showCreateFolderDialog) {
                createGroupDialogView
            }
    }
    
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEachStore(
                            self.store.scope(state: \.groups,
                                             action: GroupStore.Action.group)
                         ) { store in
                            GroupRowView(store: store)
                                .padding(.horizontal, 8)
                        }
                        .onChange(of: viewStore.trashedFilesCount) { count in
                            if count == 0 && viewStore.currentGroup?.groupType == .trash {
                                viewStore.send(.setCurrentGroup(group: nil))
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .watchImmediately(of: viewStore.currentGroup) { newValue in
                        if newValue == nil {
                            self.store.send(.setCurrentGroupToFirst)
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
            .onAppear {
                viewStore.send(.fetchGroups)
            }
        }
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
        self.store.withState { state in
            let name = "New Folder"
            var result = name
            var i = 1
            while state.groups.first(where: {$0.group.name == result}) != nil {
                result = "\(name) \(i)"
                i += 1
            }
            newFolderName = result
        }
    }
    
    func createFolder() {
        self.store.send(.createGroup(name: newFolderName))
        showCreateFolderDialog = false
    }
}

#if DEBUG
struct GroupSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        GroupSidebarView(
            store: .init(
                initialState: .init(
                    groups: .init(arrayLiteral: .init(group: Group.preview, isSelected: false))
                ),
                reducer: {
                    GroupStore()
                }
            )
        )
    }
}
#endif
 
