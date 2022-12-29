//
//  AppState.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import Foundation
import Combine

struct AppState {
    var assetFiles: [FileInfo] = []
    var currentFile: URL? = nil
    var anyFileNameInEdit: Bool = false
}

enum AppAction {
    case setCurrentFile(_ file: URL?)
    case loadAssets
    case toggleFileNameEdit
}

typealias AppStore = Store<AppState, AppAction, AppEnvironment>

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer { state, action, environment in
    switch action {
        case .setCurrentFile(let file):
            state.currentFile = file
            
        case .loadAssets:
            state.assetFiles = environment.fileManager.loadAssets()
            
        case .toggleFileNameEdit:
            state.anyFileNameInEdit.toggle()
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
