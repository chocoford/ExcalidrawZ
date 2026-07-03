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
    /// `didSet` enforces mutual exclusion with compact AI chat surfaces:
    /// opening the inspector on the aiChat tab while the island / compact
    /// toolbar prompt is up would mean two presentations of the same
    /// conversation — close the compact surface instead.
    @Published var isInspectorPresented: Bool = false {
        didSet {
            collapseCompactAISurfacesIfShowingAIChatInspector()
        }
    }

    /// The tab whose content is shown when the inspector is open.
    /// Persists across open/close cycles.
    @Published var activeInspectorTab: InspectorTab = .library {
        didSet {
            collapseCompactAISurfacesIfShowingAIChatInspector()
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

    /// Compact iOS-only presentation where the bottom toolbar swaps its
    /// regular controls for the AI prompt input. Kept separate from
    /// `isAIChatIslandMode` because the surface is no longer a floating
    /// island even though it reuses the compact input styling.
    @Published var isCompactAIChatToolbarPresented: Bool = false {
        didSet {
            guard isCompactAIChatToolbarPresented else {
                isCompactAIChatInputEditing = false
                isCompactAIChatAttachmentPickerPresented = false
                isCompactAIChatReplyTickerVisible = false
                isCompactAIChatReplyStartPending = false
                return
            }
            if isInspectorPresented && activeInspectorTab == .aiChat {
                isInspectorPresented = false
            }
            isAIChatIslandMode = false
        }
    }

    @Published var isCompactAIChatInputEditing: Bool = false

    /// True while compact iOS AI chat is presenting a system attachment
    /// picker. Keyboard hide notifications during that transition should not
    /// collapse the prompt overlay, otherwise SwiftUI tears down the picker
    /// presenter mid-presentation.
    @Published var isCompactAIChatAttachmentPickerPresented: Bool = false

    /// True while the compact iOS AI reply ticker is visible, including
    /// its short post-generation linger. The bottom toolbar uses this to
    /// avoid restoring its normal AI controls before the ticker disappears.
    @Published var isCompactAIChatReplyTickerVisible: Bool = false

    /// Compact iOS-only bridge state between a successful prompt submit and
    /// LLMKit reporting the conversation as running. It lets the bottom
    /// toolbar show Stop while the compact reply ticker renders its pending
    /// state.
    @Published var isCompactAIChatReplyStartPending: Bool = false

    /// Compact iOS-only full chat route. Owned at the editor/layout level so
    /// all compact AI entry points push the same `AIChatView` destination
    /// instead of each overlay carrying its own navigation state.
    @Published var isCompactAIChatFullChatPresented: Bool = false
    @Published var editorRouteRequest: EditorRoute?

    /// Persistent drag offset of the island (relative to its default top-right
    /// anchor). Lives here — not in the island view's @State — so the position
    /// survives unmount/remount when the island is shown/hidden.
    @Published var aiChatIslandOffset: CGSize = .zero

    /// Open the island; close the inspector if it was showing aiChat.
    func enterAIChatIsland() {
        isCompactAIChatToolbarPresented = false
        isCompactAIChatInputEditing = false
        if isInspectorPresented && activeInspectorTab == .aiChat {
            isInspectorPresented = false
        }
        isAIChatIslandMode = true
    }

    /// Close the island; reopen the inspector on the aiChat tab.
    func exitAIChatIsland() {
        isAIChatIslandMode = false
        isCompactAIChatToolbarPresented = false
        isCompactAIChatInputEditing = false
        activeInspectorTab = .aiChat
        isInspectorPresented = true
    }

    func enterCompactAIChatToolbar() {
        withAnimation(.smooth) {
            if isInspectorPresented && activeInspectorTab == .aiChat {
                isInspectorPresented = false
            }
            isAIChatIslandMode = false
            isCompactAIChatToolbarPresented = true
            isCompactAIChatInputEditing = false
        }
    }

    func enterCompactAIChatInputEditing() {
        withAnimation(.smooth) {
            if !isCompactAIChatToolbarPresented {
                enterCompactAIChatToolbar()
            }
            isCompactAIChatInputEditing = true
        }
    }

    func exitCompactAIChatInputEditing() {
        withAnimation(.smooth) {
            isCompactAIChatInputEditing = false
        }
    }

    func exitCompactAIChatToolbar() {
        withAnimation(.smooth) {
            isCompactAIChatToolbarPresented = false
            isCompactAIChatInputEditing = false
            isCompactAIChatAttachmentPickerPresented = false
            isCompactAIChatReplyTickerVisible = false
            isCompactAIChatReplyStartPending = false
        }
    }

    func presentCompactAIChatFullChat() {
        editorRouteRequest = .aiChat
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
    /// presenting the AI chat tab forces compact AI surfaces closed. The
    /// reverse directions are handled by the individual enter methods, so the
    /// presentations can never overlap regardless of which one was triggered
    /// first.
    private func collapseCompactAISurfacesIfShowingAIChatInspector() {
        guard isAIChatIslandMode || isCompactAIChatToolbarPresented else { return }
        if isInspectorPresented, activeInspectorTab == .aiChat {
            isAIChatIslandMode = false
            isCompactAIChatToolbarPresented = false
            isCompactAIChatInputEditing = false
        }
    }
}
