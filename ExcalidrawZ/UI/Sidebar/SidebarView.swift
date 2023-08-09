//
//  SidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/30.
//

import SwiftUI
import ComposableArchitecture

@dynamicMemberLookup
struct SidebarBaseState<State: Equatable>: Equatable {
    var currentFile: File? = nil
    var errors: [AppError] = []
    
    var groups: [Group] = []
    var currentGroup: Group? = nil

    var state: State
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, T>) -> T {
        get { self.state[keyPath: keyPath] }
        set { self.state[keyPath: keyPath] = newValue }
    }
}

extension SidebarBaseState: Identifiable where State: Identifiable {
    var id: State.ID { self.state.id }
}


struct SidebarStore: ReducerProtocol {
//    typealias State = AppBaseState<_State>
    struct State: Equatable {
        var currentFile: File? = nil
        var errors: [AppError] = []
        
        var groups: [Group] = []
        var currentGroup: Group? = nil

        var group: GroupStore._State = .init()
        var file: FileStore._State = .init()
        
        var groupState: GroupStore.State {
            get {
                SidebarBaseState(
                    currentFile: self.currentFile,
                    errors: self.errors,
                    groups: self.groups,
                    currentGroup: self.currentGroup,
                    state: self.group
                )
            }
            set {
                self.currentFile = newValue.currentFile
                self.errors = newValue.errors
                
                self.groups = newValue.groups
                self.currentGroup = newValue.currentGroup
                
                self.group = newValue.state
            }
        }
        
        var fileState: FileStore.State {
            get {
                SidebarBaseState(
                    currentFile: self.currentFile,
                    errors: self.errors,
                    groups: self.groups,
                    currentGroup: self.currentGroup,
                    state: self.file
                )
            }
            set {
                self.currentFile = newValue.currentFile
                self.errors = newValue.errors
                
                self.groups = newValue.groups
                self.currentGroup = newValue.currentGroup
                
                self.file = newValue.state
            }
        }
    }
    
    enum Action: Equatable {
        case group(GroupStore.Action)
        case file(FileStore.Action)
    }
    
    var body: some ReducerProtocol<State, Action> {
        Scope(state: \.groupState, action: /Action.group) {
            GroupStore()
        }
        
        Scope(state: \.fileState, action: /Action.file) {
            FileStore()
        }
        
        Reduce { state, action in
            switch action {
                case .file(.fileRow(_, .delegate(let action))):
                    switch action {
                        case .didDeleteFile, .didRecoverFile:
                            return .send(.group(.fetchTrashedFiles))
                        default:
                            return .none
                    }
                    
                case .group, .file:
                    return .none
            }
        }
    }
}

struct SidebarView: View {
    let store: StoreOf<SidebarStore>
    
    var body: some View {
        HStack(spacing: 0) {
            GroupListView(
                store: self.store.scope(state: \.groupState,
                                        action: SidebarStore.Action.group)
            )
            .frame(minWidth: 150)
            
            Divider()
            
            FileListView(
                store: self.store.scope(state: \.fileState,
                                        action: SidebarStore.Action.file)
            )
            .frame(minWidth: 200)
        }
        .border(.top, color: .separatorColor)
    }
}

#Preview {
    SidebarView(
        store: .init(initialState: .init()) {
            SidebarStore()
        }
    )
}
