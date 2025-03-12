//
//  Error.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import Foundation

struct IdentifiableError: Equatable {
    static func == (lhs: IdentifiableError, rhs: IdentifiableError) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: UUID
    var error: Error
    init(_ error: Error) {
        self.id = UUID()
        self.error = error
    }
}

enum AppError: LocalizedError, Equatable {
    case stateError(_ error: StateError)
    case fileError(_ error: FileError)
    case groupError(_ error: GroupError)
    case exportError(_ error: ExportError)
    case urlError(_ error: URLError)
    case unexpected(_ error: IdentifiableError)
    
    init(_ error: Error) {
        switch error {
            case let error as StateError:
                self = .stateError(error)
                
            case let error as FileError:
                self = .fileError(error)
                
            case let error as ExportError:
                self = .exportError(error)
                
            case let error as GroupError:
                self = .groupError(error)
            
            case let error as URLError:
                self = .urlError(error)
                
            default:
                self = .unexpected(.init(error))
        }
    }
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error.error.localizedDescription)"
            case .stateError(let error):
                return error.errorDescription
            case .fileError(let error):
                return error.errorDescription
            case .exportError(let error):
                return error.errorDescription
            case .groupError(let error):
                return error.errorDescription
            case .urlError(let error):
                return error.errorDescription
        }
    }
}

enum StateError: LocalizedError, Equatable {
    case currentGroupNil
    
    var errorDescription: String? {
        switch self {
            case .currentGroupNil:
                return "Current group is nil."
        }
    }
}

enum FileError: LocalizedError, Equatable {
    case unexpected(_ error: IdentifiableError)
    case notFound
    case invalidURL
    case createError
    case alreadyExist
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error.error.localizedDescription)"
            case .notFound:
                return "File not found."
                
            case .invalidURL:
                return "Invalid URL."
            case .createError:
                return "Create file failed."
            case .alreadyExist:
                return "File already exists."
        }
    }
}

enum ExportError: LocalizedError {
    case emptyFile
    
    var errorDescription: String? {
        switch self {
            case .emptyFile:
                "File is empty."
        }
    }
}

enum GroupError: LocalizedError, Equatable {
    case unexpected(_ error: IdentifiableError)
    case notFound(_ tag: String? = nil)
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error.error.localizedDescription)"
            case .notFound(let tag):
                return "Group not found(\(tag ?? "unknown"))."
        }
    }
}

enum DirMonitorError: LocalizedError, Equatable {
    case unexpected(_ error: IdentifiableError)
    case startFailed
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error.error.localizedDescription)"
                
            case .startFailed:
                return "Directory monitor start failed."
        }
    }
}

enum URLError: LocalizedError, Equatable {
    case startAccessingSecurityScopedResourceFailed
}

//struct ErrorBus {
//    private var continuation: AsyncStream<Error>.Continuation? = nil
//    
//    var errorStream: AsyncStream<Error>!
//    
//    init() {
//        self.errorStream = AsyncStream { continuation in
//            self.continuation = continuation
//        }
//    }
//    
//    func submit(_ error: Error) {
//        self.continuation?.yield(error)
//    }
//}
//
//extension ErrorBus: DependencyKey {
//    static var liveValue: ErrorBus {
//        .init()
//    }
//}
//
//extension DependencyValues {
//    var errorBus: ErrorBus {
//        get { self[ErrorBus.self] }
//        set { self[ErrorBus.self] = newValue }
//    }
//}
