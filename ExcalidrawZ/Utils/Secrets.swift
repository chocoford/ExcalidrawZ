//
//  Secrets.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/14/25.
//

import Foundation

struct Secrets {
    static let shared = Secrets()
    
    let collabURL: URL
    
    private init() {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            fatalError("Unable to load Secrets.plist.")
        }
        
        let collabURL = URL(string: dict["COLLAB_URL"] as? String ?? "")!
        self.collabURL = collabURL
    }
}
