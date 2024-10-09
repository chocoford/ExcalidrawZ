//
//  SegmentedPickerEnvironment.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI

private struct SegmentedPickerItemKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}

private struct SegmentedPickerItemValue: EnvironmentKey {
    static let defaultValue: (any Hashable)? = nil
}


extension EnvironmentValues {
    public internal(set) var segmentedPickerItem: (any Hashable)? {
        get { self[SegmentedPickerItemValue.self] }
        set { self[SegmentedPickerItemValue.self] = newValue }
    }
}


extension View {
    @MainActor @ViewBuilder
    public func segmentedPickerItem(_ value: any Hashable) -> some View {
        environment(\.segmentedPickerItem, value)
    }
}
