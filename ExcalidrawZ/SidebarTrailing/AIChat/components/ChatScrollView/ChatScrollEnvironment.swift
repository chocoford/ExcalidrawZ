//
//  ChatScrollEnvironment.swift
//  ExcalidrawZ
//

import SwiftUI

private struct AIChatTableRowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct AIChatUsesNativeRowHeightCacheKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var aiChatTableRowWidth: CGFloat? {
        get { self[AIChatTableRowWidthKey.self] }
        set { self[AIChatTableRowWidthKey.self] = newValue }
    }

    var aiChatUsesNativeRowHeightCache: Bool {
        get { self[AIChatUsesNativeRowHeightCacheKey.self] }
        set { self[AIChatUsesNativeRowHeightCacheKey.self] = newValue }
    }
}
