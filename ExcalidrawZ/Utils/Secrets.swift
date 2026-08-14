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
    let oneDriveClientID: String?
    let googleDriveClientID: String?
    
    private init() {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            fatalError("Unable to load Secrets.plist.")
        }
        
        let collabURL = URL(string: dict["COLLAB_URL"] as? String ?? "")!
        self.collabURL = collabURL
        self.oneDriveClientID = (dict["ONEDRIVE_CLIENT_ID"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
#if os(macOS)
        self.googleDriveClientID = (dict["GOOGLE_DRIVE_MACOS_CLIENT_ID"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
#else
        self.googleDriveClientID = (dict["GOOGLE_DRIVE_IOS_CLIENT_ID"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
#endif
    }
}
