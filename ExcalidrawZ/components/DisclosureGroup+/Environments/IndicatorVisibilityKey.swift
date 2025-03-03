//
//  DisclosureGroupIndicatorVisibilityKey.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

public enum DisclosureGroupIndicatorVisibility {
    case hidden, visible
}

struct DisclosureGroupIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: DisclosureGroupIndicatorVisibility = .visible
}

extension EnvironmentValues {
    var disclosureGroupIndicatorVisibility: DisclosureGroupIndicatorVisibility {
        get { self[DisclosureGroupIndicatorVisibilityKey.self] }
        set { self[DisclosureGroupIndicatorVisibilityKey.self] = newValue }
    }
}

extension View {
    @MainActor @ViewBuilder
    public func disclosureGroupIndicatorVisibility(
        _ visibility: DisclosureGroupIndicatorVisibility
    ) -> some View {
        environment(\.disclosureGroupIndicatorVisibility, visibility)
    }
}
