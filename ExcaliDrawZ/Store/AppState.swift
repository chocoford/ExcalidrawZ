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
    var currentGroup: URL = AppFileManager.shared.defaultGroupURL
    var anyFileNameInEdit: Bool = false
    
    var hasError: Bool = false
    var error: AppError? = nil
}

enum AppAction {
    case setCurrentGroup(_ group: URL)
    case setCurrentFile(_ file: URL?)
    case loadAssets
    case toggleFileNameEdit
    
    // error
    case setHasError(_ hasError: Bool)
    case setError(_ error: AppError)
}

typealias AppStore = Store<AppState, AppAction, AppEnvironment>

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer { state, action, environment in
    switch action {
        case .setCurrentGroup(let group):
            state.currentGroup = group
            
        case .setCurrentFile(let file):
            state.currentFile = file
            
        case .loadAssets:
            state.assetFiles = environment.fileManager.loadAssets()
            
        case .toggleFileNameEdit:
            state.anyFileNameInEdit.toggle()
            
        case .setHasError(let hasError):
            state.hasError = hasError
            
        case .setError(let error):
            state.error = error
            state.hasError = true
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
