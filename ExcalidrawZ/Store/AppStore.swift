//
//  AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/25.
//

import Foundation
import ComposableArchitecture

struct AppStore: ReducerProtocol {
    enum State: Equatable {
        case contentView(AppViewStore.State)
        
        init() { self = .contentView(AppViewStore.State()) }
    }
    
    enum Action: Equatable {
        case contentView(AppViewStore.Action)
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .contentView:
                    return .none
            }
        }
    }
}
