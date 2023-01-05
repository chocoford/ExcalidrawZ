//
//  AppState.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import Foundation
import Combine

struct AppState {
    var assetGroups: [GroupInfo] = []
    var assetFiles: [FileInfo] = []
    var currentFile: URL? = nil
    var currentGroup: GroupInfo = GroupInfo(url: AppFileManager.shared.defaultGroupURL)
    var anyFileNameInEdit: Bool = false
    
    var hasError: Bool = false
    var error: AppError? = nil
}

enum AppAction {
    case setCurrentGroup(_ group: GroupInfo)
    case setCurrentFile(_ file: URL?)
    case loadAssets
    
    case newFile
    case importFile(_ file: URL)
    case renameFile(of: FileInfo, newName: String)
    case deleteFile(_ file: FileInfo)
    
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
            if file == nil && state.assetFiles.count > 0 {
                break
            }
            state.currentFile = file
            
        case .loadAssets:
            state.assetGroups = environment.fileManager.loadGroups()
            state.assetFiles = environment.fileManager.loadFiles(in: state.currentGroup)
            
        case .newFile:
            guard let newFile = environment.fileManager.createNewFile(at: state.currentGroup.url) else {
                return Just(.setError(.fileError(.createError)))
                    .eraseToAnyPublisher()
            }
            state.assetFiles.insert(newFile, at: 0)
            return Just(.setCurrentFile(newFile.url))
                .eraseToAnyPublisher()
            
        case .importFile(let url):
            do {
                let fileURL = try environment.fileManager.importFile(from: url, to: state.currentGroup)
                state.assetFiles.insert(FileInfo(from: fileURL), at: 0)
                return Just(.setCurrentFile(fileURL))
                    .eraseToAnyPublisher()
            } catch let error as FileError {
                return Just(AppAction.setError(.fileError(error)))
                    .eraseToAnyPublisher()
            } catch {
                return Just(AppAction.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .renameFile(let file, let name):
            do {
                var isCurrentFile = false
                if file.url == state.currentFile {
                    isCurrentFile = true
                }
                guard let fileIndex = state.assetFiles.firstIndex(of: file) else { throw FileError.notFound }
                // It will trigger file info change. Causing `List` change its selection.
                // But the procedure is not synchronizign.
                try environment.fileManager.renameFile(file.url, to: name)
                state.assetFiles[fileIndex].rename(to: name)
                
                if isCurrentFile {
                    // Use async on main thread to make sure `setCurrentFile` will execute after `List`'s selection changing.
                    return Just(.setCurrentFile(state.assetFiles[fileIndex].url)).eraseToAnyPublisher()
                }
            } catch let error as FileError {
                return Just(AppAction.setError(.fileError(error)))
                    .eraseToAnyPublisher()
            } catch {
                return Just(AppAction.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .deleteFile(let file):
            do {
                guard let index = state.assetFiles.firstIndex(of: file) else { throw FileError.notFound }
                try environment.fileManager.removeFile(at: file.url)
                state.assetFiles.remove(at: index)
                if state.currentFile == file.url {
                    return Just(.setCurrentFile(state.assetFiles.safeSubscribe(at: index)?.url))
                        .eraseToAnyPublisher()
                }
            } catch let error as FileError {
                return Just(AppAction.setError(.fileError(error)))
                    .eraseToAnyPublisher()
            } catch {
                return Just(AppAction.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
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
