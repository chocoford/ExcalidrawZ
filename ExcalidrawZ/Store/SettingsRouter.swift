//
//  SettingsRouter.swift
//  ExcalidrawZ
//
//  Tiny app-level signal bus for "open Settings to tab X" deep-links.
//
//  `LayoutState` would have been the natural home, but it's a per-window
//  `@StateObject` (created in `ContentView` and again inside collaboration
//  stacks) — the `Settings { ... }` scene at App level doesn't share that
//  instance, so a published value there wouldn't reach the Settings UI.
//
//  This singleton owns *only* the deep-link state. Actually opening the
//  Settings scene is the caller's responsibility — preferably via
//  `SettingsLink` (macOS 14+ / iOS 17+), which is the only path that
//  doesn't trip the macOS 26+ runtime warning
//  "Please use SettingsLink for opening the Settings scene." Older OS
//  fallbacks may use `NSApp.sendAction(showSettingsWindow:)` via
//  `requestOpen(_:)` since those versions don't carry the warning.
//
//  Single-shot — `SettingsView` clears `pendingRoute` after applying it so
//  a re-open doesn't sticky-route to the previous tab.
//

import SwiftUI
import Combine

final class SettingsRouter: ObservableObject {
    @MainActor static let shared = SettingsRouter()

    enum AISettingsRoute {
        case usage
        case settings
    }

    /// Tab to switch to the next time `SettingsView` appears or this value
    /// changes. Cleared by `SettingsView` after consumption.
    @Published var pendingRoute: SettingsView.Route?
    @Published var pendingAISettingsRoute: AISettingsRoute?

    private init() {}

    /// Legacy/fallback: set the deep-link target *and* trigger the Settings
    /// window via NSApp action. macOS 14+ / iOS 17+ should prefer
    /// `SettingsLink` paired with a `simultaneousGesture` that writes
    /// `pendingRoute` directly — that route avoids the runtime warning that
    /// macOS 26+ emits when Settings is opened any other way.
    func requestOpen(_ route: SettingsView.Route) {
        pendingRoute = route
#if os(macOS)
        // `showSettingsWindow:` on macOS 13+, `showPreferencesWindow:` on
        // older. `sendAction` returns false if no responder handled it; try
        // the legacy selector as a safety net.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
#endif
    }

    func requestOpenAIUsage() {
        pendingAISettingsRoute = .usage
        requestOpen(.ai)
    }
}
