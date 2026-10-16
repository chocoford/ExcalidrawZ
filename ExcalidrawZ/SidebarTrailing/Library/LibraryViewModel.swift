//
//  LibraryViewModel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import Observation
import SwiftUI

@Observable
class LibraryViewModel {
    private(set) var libraryViewID: String = UUID().uuidString
    private(set) var metadataRevision = 0
    
    var excalidrawWebCoordinator: ExcalidrawCanvasView.Coordinator?
    
    func refreshLibraryMetadata() {
        metadataRevision &+= 1
    }

    public func forceLibraryViewUpdate() {
        self.libraryViewID = UUID().uuidString
    }
}
