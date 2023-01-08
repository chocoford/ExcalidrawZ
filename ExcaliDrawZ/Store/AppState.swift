//
//  AppState.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import Foundation
import Combine
import CoreData

struct AppState {
    var groups: [Group] = []
    var files: [File] = []
    var currentFile: File? = nil
    var currentGroup: Group? = nil
    
//    var currentGroup: Group? {
//        guard let currentGroupID = currentGroupID else { return nil }
//
//    }
    
    var anyFileNameInEdit: Bool = false
    
    var hasError: Bool = false
    var error: AppError? = nil
}

enum AppAction {
    case setGroups(_ groups: [Group])
    case setFiles(_ files: [File])
    
    case setCurrentGroup(_ groupID: Group?)
    case setCurrentFile(_ file: File?)
//    case loadAssets
    
    case newFile(_ elementsData: Data? = nil)
    case importFile(_ file: URL)
    case renameFile(of: FileInfo, newName: String)
    case deleteFile(_ file: FileInfo)
    
    case createGroup(_ name: String)
    
    case toggleFileNameEdit
    
    // error
    case setHasError(_ hasError: Bool)
    case setError(_ error: AppError)
}

typealias AppStore = Store<AppState, AppAction, AppEnvironment>

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer { state, action, environment in
    switch action {
        case .setGroups(let groups):
            state.groups = groups
        case .setFiles(let files):
            state.files = files
            
        case .setCurrentGroup(let group):
            guard group != nil else { break }
            state.currentGroup = group
//            state.assetFiles = environment.fileManager.loadFiles(in: state.currentGroup)
//            state.currentFile = state.assetFiles.first?.url
            
        case .setCurrentFile(let file):
            guard file != nil || state.files.count > 0 else { break }
            state.currentFile = file
            
//        case .loadAssets:
//            state.groups = environment.fileManager.loadGroups()
////            state.assetFiles = environment.fileManager.loadFiles(in: state.currentGroup)

        case .createGroup(let name):
            do {
                let group = try environment.persistence.createGroup(name: name)
                state.currentGroup = group
            } catch {
                return Just(.setError(.fileError(.unexpected(error))))
                    .eraseToAnyPublisher()
            }
            
            
        case .newFile(let elementsData):
            do {
                guard let group = state.currentGroup else { throw AppError.stateError(.currentGroupNil) }
                let file = try environment.persistence.createFile(in: group)
                if let data = elementsData { try file.updateElements(with: data) }
                state.currentFile = file
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .importFile(let url):
            break
//            do {
//                let fileURL = try environment.fileManager.importFile(from: url, to: state.currentGroup)
//                state.assetFiles.insert(FileInfo(from: fileURL), at: 0)
////                return Just(.setCurrentFile(fileURL))
////                    .eraseToAnyPublisher()
//            } catch let error as FileError {
//                return Just(AppAction.setError(.fileError(error)))
//                    .eraseToAnyPublisher()
//            } catch {
//                return Just(AppAction.setError(.unexpected(error)))
//                    .eraseToAnyPublisher()
//            }
            
        case .renameFile(let file, let name):
            break
//            do {
//                var isCurrentFile = false
//                if file.url == state.currentFile {
//                    isCurrentFile = true
//                }
//                guard let fileIndex = state.assetFiles.firstIndex(of: file) else { throw FileError.notFound }
//                // It will trigger file info change. Causing `List` change its selection.
//                // But the procedure is not synchronizign.
//                try environment.fileManager.renameFile(file.url, to: name)
//                state.assetFiles[fileIndex].rename(to: name)
//
//                if isCurrentFile {
//                    // Use async on main thread to make sure `setCurrentFile` will execute after `List`'s selection changing.
//                    return Just(.setCurrentFile(state.assetFiles[fileIndex].url)).eraseToAnyPublisher()
//                }
//            } catch let error as FileError {
//                return Just(AppAction.setError(.fileError(error)))
//                    .eraseToAnyPublisher()
//            } catch {
//                return Just(AppAction.setError(.unexpected(error)))
//                    .eraseToAnyPublisher()
//            }
            
        case .deleteFile(let file):
            break
//            do {
//                guard let index = state.assetFiles.firstIndex(of: file) else { throw FileError.notFound }
//                try environment.fileManager.removeFile(at: file.url)
//                state.assetFiles.remove(at: index)
//                if state.currentFile == file.url {
//                    return Just(.setCurrentFile(state.assetFiles.safeSubscribe(at: index)?.url))
//                        .eraseToAnyPublisher()
//                }
//            } catch let error as FileError {
//                return Just(AppAction.setError(.fileError(error)))
//                    .eraseToAnyPublisher()
//            } catch {
//                return Just(AppAction.setError(.unexpected(error)))
//                    .eraseToAnyPublisher()
//            }
            

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
