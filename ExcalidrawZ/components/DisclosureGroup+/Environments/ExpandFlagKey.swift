//
//  DisclosureExpandFlag.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

struct DisclosureGroupExpandFlagKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var disclosureGroupExpandFlagKey: Bool {
        get { self[DisclosureGroupExpandFlagKey.self] }
        set { self[DisclosureGroupExpandFlagKey.self] = newValue }
    }
}
