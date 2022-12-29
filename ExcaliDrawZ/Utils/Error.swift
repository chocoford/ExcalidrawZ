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

    var errorDescription: String? {
        switch self {
            case .renameError(let error):
                return error.errorDescription
            case .deleteError(let error):
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

