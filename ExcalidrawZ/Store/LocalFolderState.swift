//
//  LocalFolderState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/27/25.
//

import SwiftUI
import Combine

final class LocalFolderState: ObservableObject {
    var itemRemovedPublisher = PassthroughSubject<String, Never>()
    var itemCreatedPublisher = PassthroughSubject<String, Never>()
    var itemUpdatedPublisher = PassthroughSubject<String, Never>()
}
