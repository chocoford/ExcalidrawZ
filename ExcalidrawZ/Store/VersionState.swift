//
//  VersionState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/4.
//

import Observation
import Foundation

@Observable
class VersionState {
    
    var version: String
    
    init() {
        version = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
    }
}
