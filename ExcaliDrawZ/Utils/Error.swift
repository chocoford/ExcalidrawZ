//
//  Error.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import Foundation

enum AppError: LocalizedError {
    case unexpected(_ error: Error?)
    case fileError(_ error: FileError)
    case dirMonitorError(_ error: DirMonitorError)
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
            case .fileError(let error):
                return error.errorDescription
            case .dirMonitorError(let error):
                return error.errorDescription
        }
    }
}

enum FileError: LocalizedError {
    case unexpected(_ error: Error?)
    case notFound
    case invalidURL
    case createError
    case alreadyExist
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
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

enum DirMonitorError: LocalizedError {
    case unexpected(_ error: Error?)
    case startFailed
    
    var errorDescription: String? {
        switch self {
            case .unexpected(let error):
                return "Unexpected error: \(error?.localizedDescription ?? "nil")"
                
            case .startFailed:
                return "Directory monitor start failed."
        }
    }
}
