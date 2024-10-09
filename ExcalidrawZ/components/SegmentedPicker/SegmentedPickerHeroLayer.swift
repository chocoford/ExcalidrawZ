//
//  SegmentedPickerPreferenceKey.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/11.
//

import SwiftUI
 
struct SegmentedPickerPreferenceKey: PreferenceKey {
    static var defaultValue: [Int : Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [Int : Anchor<CGRect>], nextValue: () -> [Int : Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}


