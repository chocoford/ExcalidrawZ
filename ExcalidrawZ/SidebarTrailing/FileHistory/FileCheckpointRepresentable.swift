//
//  FileCheckpointRepresentable.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/25/25.
//

import Foundation
import CoreData

protocol FileCheckpointRepresentable: Equatable, Identifiable, NSManagedObject {
    var fileID: String? { get }
    var updatedAt: Date? { get }
    var filename: String? { get }
    var content: Data? { get }
}

extension FileCheckpoint: FileCheckpointRepresentable {
    var fileID: String? {
        file?.id?.uuidString
    }
}

extension LocalFileCheckpoint: FileCheckpointRepresentable {
    var filename: String? {
        url?.deletingPathExtension().lastPathComponent
    }
    var fileID: String? { nil }
}
 
