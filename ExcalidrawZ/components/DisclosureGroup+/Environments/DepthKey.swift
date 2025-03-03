//
//  DisclosureGroupDepthKey.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

struct DisclosureGroupDepthKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    var diclosureGroupDepth: Int {
        get { self[DisclosureGroupDepthKey.self] }
        set { self[DisclosureGroupDepthKey.self] = newValue }
    }
}
