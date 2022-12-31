//
//  Error.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import Foundation

enum AppError: LocalizedError {
    case renameError(_ error: RenameError)
    case deleteError(_ error: DeleteError)
    case importError(_ error: ImportError)
    
    var errorDescription: String? {
        switch self {
            case .renameError(let error):
                return error.errorDescription
            case .deleteError(let error):
                return error.errorDescription
            case .importError(let error):
                return error.errorDescription
        }
    }
}



enum RenameError: LocalizedError {
    case unexpected(_ error: Error?)
    case notFound
    
    var errorDescription: String? {
        switch self {
            case .notFound:
                return "File not found."
                
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
                
        }
    }
}

enum DeleteError: LocalizedError {
    case unexpected(_ error: Error?)
    case nameError
    case notFound
    
    var errorDescription: String? {
        switch self {
            case .nameError:
                return "File name error."
                
            case .notFound:
                return "File not found."
                
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
                
        }
    }
}

enum ImportError: LocalizedError {
    case unexpected(_ error: Error?)
    case invalidURL
    case createError
    case alreadyExist
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
            case .invalidURL:
                return "Invalid URL."
            case .createError:
                return "Create file failed."
            case .alreadyExist:
                return "File already exists."
        }
    }
}
