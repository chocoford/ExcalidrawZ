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
    
    var anyFileNameInEdit: Bool = false
    
    var hasError: Bool = false
    var error: AppError? = nil
}

enum AppAction {
    case setCurrentGroup(_ groupID: Group?)
    case setCurrentGroupToFirst
    case setCurrentFile(_ file: File?)
    case setCurrentFileToFirst
    
    case newFile(_ elementsData: Data? = nil)
    case importFile(_ file: URL)
    case renameFile(of: File, newName: String)
    case deleteFile(_ file: File)
    
    case createGroup(_ name: String)
    
    case saveCoreData
    
    case toggleFileNameEdit
    
    // error
    case setHasError(_ hasError: Bool)
    case setError(_ error: AppError)
}

typealias AppStore = Store<AppState, AppAction, AppEnvironment>

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer { state, action, environment in
    switch action {
        case .setCurrentGroup(let group):
            guard group != nil else { break }
            state.currentGroup = group
            do {
                if let group = group {
                    state.currentFile = try environment.persistence.listFiles(in: group).first
                } else {
                    throw AppError.stateError(.currentGroupNil)
                }
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .setCurrentGroupToFirst:
            do {
                state.currentGroup = try environment.persistence.listGroups().first
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .setCurrentFile(let file):
            guard file != nil || state.files.count > 0 else { break }
            state.currentFile = file
            
        case .setCurrentFileToFirst:
            do {
                if let group = state.currentGroup {
                    state.currentFile = try environment.persistence.listFiles(in: group).first
                } else {
                    throw AppError.stateError(.currentGroupNil)
                }
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
                
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
            do {
                guard url.pathExtension == "excalidraw" else { throw AppError.fileError(.invalidURL) }
                let data = try Data(contentsOf: url, options: .uncached) // .uncached fixes the import bug occurs in x86 mac OS

                guard let group = state.currentGroup else { throw AppError.stateError(.currentGroupNil) }
                let file = try environment.persistence.createFile(in: group)
                file.name = String(url.lastPathComponent.split(separator: ".").first ?? "Untitled")
                file.content = data
                
                state.currentFile = file
            } catch let error as FileError {
                return Just(AppAction.setError(.fileError(error)))
                    .eraseToAnyPublisher()
            } catch {
                return Just(AppAction.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .renameFile(let file, let name):
            file.name = name
            
        case .deleteFile(let file):
            // get current group files
            do {
                guard let group = state.currentGroup else { throw AppError.stateError(.currentGroupNil)}
                var files = try environment.persistence.listFiles(in: group)
                let index = files.firstIndex(of: file) ?? 1
                environment.persistence.container.viewContext.delete(file)
                files.remove(at: index)
                state.currentFile = files.safeSubscribe(at: index - 1)
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .saveCoreData:
            environment.persistence.save()
            
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
