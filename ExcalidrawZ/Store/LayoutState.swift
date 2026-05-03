//
//  LayoutState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/18.
//

import SwiftUI

final class LayoutState: ObservableObject {
    enum InspectorTab: Hashable {
        case aiChat
        case library
        case history
        case preference
        case search
#if DEBUG
        case debug
#endif
    }

    @Published var isSidebarPresented: Bool = true

    /// Whether the inspector is visible. Independent from `activeInspectorTab` so that
    /// closing the inspector preserves which tab the user last looked at.
    @Published var isInspectorPresented: Bool = false

    /// The tab whose content is shown when the inspector is open.
    /// Persists across open/close cycles.
    @Published var activeInspectorTab: InspectorTab = .library

    @Published var isResotreAlertIsPresented: Bool = false

    enum CompactBrowserLayout: Hashable {
        case grid
        case list
    }

    @Published var compactBrowserLayout: CompactBrowserLayout = .grid

    /// Triggered by clicking a specific tab button.
    /// - Same tab while open: close (keep the tab selected so reopening returns to it).
    /// - Different tab while open: switch tab (stay open).
    /// - Closed: assign tab first, then open — so the inspector always opens with the right content.
    func toggleInspector(_ tab: InspectorTab) {
        if isInspectorPresented {
            if activeInspectorTab == tab {
                isInspectorPresented = false
            } else {
                activeInspectorTab = tab
            }
        } else {
            activeInspectorTab = tab
            isInspectorPresented = true
        }
    }

    /// Generic open/close toggle (e.g., from a global menu shortcut). Keeps the current `activeInspectorTab`.
    func toggleInspector() {
        isInspectorPresented.toggle()
    }
}
