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
    ///
    /// `didSet` enforces mutual exclusion with the AI chat island: opening the
    /// inspector on the aiChat tab while the island is up would mean two
    /// presentations of the same conversation — close the island instead.
    @Published var isInspectorPresented: Bool = false {
        didSet {
            collapseIslandIfShowingAIChatInspector()
        }
    }

    /// The tab whose content is shown when the inspector is open.
    /// Persists across open/close cycles.
    @Published var activeInspectorTab: InspectorTab = .library {
        didSet {
            collapseIslandIfShowingAIChatInspector()
        }
    }

    @Published var isResotreAlertIsPresented: Bool = false

    enum CompactBrowserLayout: Hashable {
        case grid
        case list
    }

    @Published var compactBrowserLayout: CompactBrowserLayout = .grid

    // MARK: - AI Chat island

    /// When true, the AI chat is presented as a floating, draggable island
    /// over the editor instead of as a sidebar inspector. Mutually exclusive
    /// with `isInspectorPresented + activeInspectorTab == .aiChat` (toggling
    /// island on closes the inspector if it was on aiChat; toggling off
    /// reopens it on aiChat).
    @Published var isAIChatIslandMode: Bool = false

    /// Persistent drag offset of the island (relative to its default top-right
    /// anchor). Lives here — not in the island view's @State — so the position
    /// survives unmount/remount when the island is shown/hidden.
    @Published var aiChatIslandOffset: CGSize = .zero

    /// Open the island; close the inspector if it was showing aiChat.
    func enterAIChatIsland() {
        if isInspectorPresented && activeInspectorTab == .aiChat {
            isInspectorPresented = false
        }
        isAIChatIslandMode = true
    }

    /// Close the island; reopen the inspector on the aiChat tab.
    func exitAIChatIsland() {
        isAIChatIslandMode = false
        activeInspectorTab = .aiChat
        isInspectorPresented = true
    }

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

    /// Mutual-exclusion guard: any path that ends up with the inspector
    /// presenting the AI chat tab forces the island closed. Both the reverse
    /// direction (open island → close aiChat inspector) is handled in
    /// `enterAIChatIsland`, so the two presentations can never overlap
    /// regardless of which one was triggered first.
    private func collapseIslandIfShowingAIChatInspector() {
        guard isAIChatIslandMode else { return }
        if isInspectorPresented, activeInspectorTab == .aiChat {
            isAIChatIslandMode = false
        }
    }
}
