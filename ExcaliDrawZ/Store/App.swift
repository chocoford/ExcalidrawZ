//
//  AppState.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import Foundation
import Combine

struct AppState {
    var currentFile: URL? = nil
}

enum AppAction {
    case setCurrentFile(_ file: URL?)
}

typealias AppStore = Store<AppState, AppAction, AppEnvironment>

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer { state, action, environment in
    switch action {
        case .setCurrentFile(let file):
            state.currentFile = file
    }
    
    return Empty()
        .eraseToAnyPublisher()
}


#if DEBUG
extension AppState {
    static let preview: AppState = {
        var previewState: AppState = .init()
        return previewState
    }()
}


extension AppStore {
    static let preview = AppStore(state: .preview,
                                  reducer: appReducer,
                                  environment: .init())
}

#endif
