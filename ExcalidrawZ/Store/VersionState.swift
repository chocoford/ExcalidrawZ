//
//  VersionState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/4.
//

import Foundation

class VersionState: ObservableObject {
    
    @Published var version: String
    
    init() {
        version = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    }
}
