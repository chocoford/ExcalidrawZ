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
    var currentGroup: Group? {
        didSet {
            UserDefaults.standard.set(currentGroup?.id?.uuidString, forKey: "selectedGroup")
        }
    }
    
    var anyFileNameInEdit: Bool = false
    
    var hasError: Bool = false
    var error: AppError? = nil
}

enum AppAction {
    case setCurrentGroup(_ group: Group?)
    case setCurrentGroupFromLastSelected
    case setCurrentFile(_ file: File?)
    case setCurrentFileToFirst
    
    case createGroup(_ name: String)
    case deleteGroup(_ group: Group)
    
    case newFile(_ elementsData: Data? = nil)
    case importFile(_ file: URL)
    case renameFile(of: File, newName: String)
    case duplicateFile(_ file: File)
    case moveFile(_ fileID: UUID, _ group: Group)
    
    case deleteFile(_ file: File, _ permanent: Bool = false)
    case recoverFile(_ file: File)
    
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
            guard group != nil else {
                let allGroups = try? environment.persistence.listGroups()
                state.currentGroup = allGroups?.first(where: {$0.groupType == .default})
                break
            }
            do {
                state.currentGroup = group
                if let group = group {
                    return Just(.setCurrentFileToFirst)
                        .eraseToAnyPublisher()
                } else {
                    throw AppError.stateError(.currentGroupNil)
                }
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .setCurrentGroupFromLastSelected:
            do {
                let allGroups = try environment.persistence.listGroups()
                if let lastGroupIDString = UserDefaults.standard.value(forKey: "selectedGroup") as? String,
                   let lastGroupID = UUID(uuidString: lastGroupIDString),
                   let lastGroup = allGroups.first(where: { $0.id == lastGroupID}) {
                    state.currentGroup = lastGroup
                } else if allGroups.first != nil {
                    // First Time
                    state.currentGroup = allGroups.first
                } else {
                    return Just(.setCurrentGroupFromLastSelected)
                        .delay(for: 1.0, scheduler: environment.delayQueue)
                        .eraseToAnyPublisher()
                }
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
                    if group.groupType == .trash {
                        if let file = try environment.persistence.listTrashedFiles().first {
                            state.currentFile = file
                        } else {
                            // no file in trash
                            return Just(.setCurrentGroup(nil))
                                .eraseToAnyPublisher()
                        }
                    } else {
                        state.currentFile = try environment.persistence.listFiles(in: group).first {
                            !$0.inTrash
                        }
                    }
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
            
        case .deleteGroup(let group):
            do {
                var groups = try environment.persistence.listGroups()
                let files = try environment.persistence.listFiles(in: group)
                let index = groups.firstIndex(of: group) ?? 0
                guard let trash = groups.first(where: { $0.groupType == .trash }) else {
                    throw AppError.fileError(.notFound)
                }
                files.forEach {
                    $0.group = trash
                }
                environment.persistence.container.viewContext.delete(group)
                groups.remove(at: index)
                state.currentGroup = groups.safeSubscribe(at: index - 1)
            } catch {
                return Just(.setError(.unexpected(error)))
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
            file.updatedAt = .now
            
        case .duplicateFile(let file):
            let newFile = environment.persistence.duplicateFile(file: file)
            state.currentFile = newFile
            
        case .moveFile(let fileID, let group):
            do {
                guard let file = try environment.persistence.findFile(id: fileID) else { throw AppError.fileError(.notFound) }
                file.group = group
                if state.currentGroup?.groupType == .trash && state.currentGroup?.files?.count == 0 {
                    return Just(.setCurrentGroup(group))
                        .eraseToAnyPublisher()
                } else {
                    return Just(.setCurrentFileToFirst)
                        .eraseToAnyPublisher()
                }
                
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
        
        case .deleteFile(let file, let permanent):
            // get current group files
            do {
                guard let group = state.currentGroup else { throw AppError.stateError(.currentGroupNil)}
                var files: [File]
                if group.groupType != .trash {
                    files = try environment.persistence.listFiles(in: group)
                } else {
                    files = try environment.persistence.listTrashedFiles()
                }
                guard let index = files.firstIndex(of: file) else { throw AppError.fileError(.notFound) }
                if permanent {
                    environment.persistence.container.viewContext.delete(file)
                } else {
                    file.inTrash = true
                    file.deletedAt = .now
                }
                files.remove(at: index)
                state.currentFile = files.safeSubscribe(at: index - 1)
            } catch {
                return Just(.setError(.unexpected(error)))
                    .eraseToAnyPublisher()
            }
            
        case .recoverFile(let file):
            do {
                guard let group = state.currentGroup,
                      group.groupType == .trash else { throw AppError.stateError(.currentGroupNil)}
                var files = try environment.persistence.listTrashedFiles()
                let index = files.firstIndex(of: file) ?? 1
                file.inTrash = false
                file.deletedAt = nil
                file.updatedAt = .now
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
