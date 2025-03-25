//
//  SpotlightDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import Foundation
import CoreData
import CoreSpotlight
import os.log

class SpotlightDelegate: NSCoreDataCoreSpotlightDelegate {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SpotlightDelegate")
    
    override func domainIdentifier() -> String {
        "com.chocoford.excalidraw.model"
    }
    
    override func indexName() -> String? {
        "model-index"
    }
    
    override func attributeSet(for object: NSManagedObject) -> CSSearchableItemAttributeSet? {
        
        if case let file as File = object {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            
            attributeSet.displayName = file.name
             
            self.logger.info("[SpotlightDelegate] attributeSet for object... \(String(describing: attributeSet))")
            
            return attributeSet
        }
        return nil
    }
}

extension PersistenceController {
    public func refreshIndices() async throws {
        self.logger.info("[PersistenceController] Refresh Spotlight Index...")
        
        self.spotlightIndexer?.stopSpotlightIndexing()
        
        // delete all indices
        try await self.spotlightIndexer?.deleteSpotlightIndex()
        
        self.spotlightIndexer?.startSpotlightIndexing()
    }
}
