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

    // New AI-history fields. Both Core Data entities now auto-generate
    // these via the schema; the protocol surface lets call sites treat
    // the two checkpoint types uniformly.
    var source: String? { get set }
    var messageID: String? { get set }
    var historyDescription: String? { get set }
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
 
