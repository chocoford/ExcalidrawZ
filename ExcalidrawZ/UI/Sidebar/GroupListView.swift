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

    typealias State = SidebarBaseState<_State>
    
    struct _State: Equatable {
        var groupRows: IdentifiedArrayOf<GroupRowStore.State> = .init()
        var trashedFilesCount: Int = 0
        
        /// groups that not deleted.
        var displayedGroups: IdentifiedArrayOf<GroupRowStore.State> {
            get {
                .init(
                    uniqueElements: self.groupRows.filter {
                        $0.group.type != .trash || ($0.group.type == .trash && self.trashedFilesCount > 0)
                    }.sorted { a, b in
                        a.group.type == .default && b.group.type != .default ||
                        a.group.type == b.group.type && b.group.type == .normal && a.group.createdAt < b.group.createdAt  ||
                        a.group.type != .trash && b.group.type == .trash
                    }
                )
            }
            set {
                newValue.forEach { rowState in
                    groupRows.updateOrAppend(rowState)
                }
            }
        }
        
//        var currentGroup: Group? {
//            get { groupRows.first(where: {$0.isSelected})?.group.groupEntity }
//            set {
//                for group in groupRows {
//                    groupRows[id: group.id]?.isSelected = group.id == newValue?.id
//                }
//            }
//        }
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
                
        case setError(AppError)
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case didSetCurrentGroup(Group?)
            case didSetGroups([Group])
        }
    }
    @Dependency(\.errorBus) var errorBus
    @Dependency(\.coreData) var coreData

    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .createGroup(let name):
                    do {
                        let group = try coreData.provider.createGroup(name: name)
                        coreData.provider.save()
                        return .run { send in
                            await send(.fetchGroups)
                            await send(.setCurrentGroup(group: group))
                        }
                    } catch {
                        return .none
                    }
                    
                case .fetchGroups:
                    do {
                        var groups = try coreData.provider.listGroups()
                        if !groups.contains(where: {$0.groupType == .trash}) {
                            groups.append(.trash)
                        }
                        return .send(.setGroups(groups: groups))
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                    
                case .setGroups(let groups):
                    state.groups = groups
                    state.state.groupRows = IdentifiedArray(
                        uniqueElements: groups.map {
                                GroupRowStore.State(group: $0, isSelected: state.currentGroup?.id == $0.id)
                            }
                    )
                    return .none
                    
                case .setCurrentGroup(let group):
                    state.currentGroup = group
                    for groupRow in state.groupRows {
                        state.groupRows[id: groupRow.id]?.isSelected = groupRow.id == group?.id
                    }
                    return .none
                    
                case .setCurrentGroupToFirst:
                    return .send(.setCurrentGroup(group: state.displayedGroups.first?.group.groupEntity))
                    
                case .group(let id, .delegate(let action)):
                    switch action {
                        case .didSetAsCurrentGroup:
                            return .send(.setCurrentGroup(group: state.state.groupRows[id: id]?.group.groupEntity))
                        case .didDeleteGroupOrEmptyTrash:
                            return .run { send in
                                await send(.fetchGroups)
                                await send(.fetchTrashedFiles)
                                await send(.setCurrentGroupToFirst)
                            }
                    }
                    
                case .group:
                    return .none
                    
                case .fetchTrashedFiles:
                    let trashedFilesCount = (try? coreData.provider.listTrashedFiles())?.count ?? 0
                    return .send(.setTrashedFilesCount(trashedFilesCount))
                    
                case .setTrashedFilesCount(let count):
                    state.trashedFilesCount = count
                    return .none
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
                    
                case .delegate:
                    return .none
            }
        }
        .forEach(\.state.displayedGroups, action: /Action.group) {
            GroupRowStore()
        }
    }
}

struct GroupListView: View {
    let store: StoreOf<GroupStore>
    
    @State private var showCreateFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        content
            .onAppear(perform: getNextFileName)
            .sheet(isPresented: $showCreateFolderDialog) {
                CreateGroupSheetView(initialName: newFolderName) { name in
                    self.store.send(.createGroup(name: name))
                }
            }
    }
    
    @ViewBuilder private var content: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEachStore(
                            self.store.scope(state: \.displayedGroups,
                                             action: GroupStore.Action.group)
                         ) { store in
                            GroupRowView(store: store)
                                .padding(.horizontal, 8)
                        }
                    }
                    .onChange(of: viewStore.trashedFilesCount) { count in
                        if count == 0 && viewStore.currentGroup?.groupType == .trash {
                            viewStore.send(.setCurrentGroup(group: nil))
                        }
                    }
                    .padding(.vertical, 12)
                    .onChange(of: viewStore.groupRows) { newValue in
                        if viewStore.currentGroup == nil {
                            self.store.send(.setCurrentGroupToFirst)
                        }
                    }
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
                viewStore.send(.fetchTrashedFiles)
            }
        }
    }
}


extension GroupListView {
    func getNextFileName() {
        self.store.withState { state in
            let name = "New Folder"
            var result = name
            var i = 1
            while state.state.groupRows.first(where: {$0.group.name == result}) != nil {
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
struct GroupSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        GroupListView(
            store: .init(
                initialState: .init(
                    groups: [Group.preview],
                    state: .init()
                ),
                reducer: {
                    GroupStore()
                }
            )
        )
    }
}
#endif
 
