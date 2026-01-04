//
//  Window+Extension.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/2/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit

// MARK: - Window Event Type

/// Enum representing NSWindow notification events
enum WindowEvent: Hashable, CaseIterable {
    case didBecomeKey
    case didBecomeMain
    case didChangeScreen
    case didDeminiaturize
    case didExpose
    case didMiniaturize
    case didMove
    case didResignKey
    case didResignMain
    case didResize
    case didUpdate
    case willClose
    case willMiniaturize
    case willMove
    case willBeginSheet
    case didEndSheet
    case didChangeBackingProperties
    case didChangeScreenProfile
    case willStartLiveResize
    case didEndLiveResize
    case willEnterFullScreen
    case didEnterFullScreen
    case willExitFullScreen
    case didExitFullScreen
    case willEnterVersionBrowser
    case didEnterVersionBrowser
    case willExitVersionBrowser
    case didExitVersionBrowser
    case didChangeOcclusionState

    /// Convert to NSNotification.Name
    var notificationName: NSNotification.Name {
        switch self {
        case .didBecomeKey:
            return NSWindow.didBecomeKeyNotification
        case .didBecomeMain:
            return NSWindow.didBecomeMainNotification
        case .didChangeScreen:
            return NSWindow.didChangeScreenNotification
        case .didDeminiaturize:
            return NSWindow.didDeminiaturizeNotification
        case .didExpose:
            return NSWindow.didExposeNotification
        case .didMiniaturize:
            return NSWindow.didMiniaturizeNotification
        case .didMove:
            return NSWindow.didMoveNotification
        case .didResignKey:
            return NSWindow.didResignKeyNotification
        case .didResignMain:
            return NSWindow.didResignMainNotification
        case .didResize:
            return NSWindow.didResizeNotification
        case .didUpdate:
            return NSWindow.didUpdateNotification
        case .willClose:
            return NSWindow.willCloseNotification
        case .willMiniaturize:
            return NSWindow.willMiniaturizeNotification
        case .willMove:
            return NSWindow.willMoveNotification
        case .willBeginSheet:
            return NSWindow.willBeginSheetNotification
        case .didEndSheet:
            return NSWindow.didEndSheetNotification
        case .didChangeBackingProperties:
            return NSWindow.didChangeBackingPropertiesNotification
        case .didChangeScreenProfile:
            return NSWindow.didChangeScreenProfileNotification
        case .willStartLiveResize:
            return NSWindow.willStartLiveResizeNotification
        case .didEndLiveResize:
            return NSWindow.didEndLiveResizeNotification
        case .willEnterFullScreen:
            return NSWindow.willEnterFullScreenNotification
        case .didEnterFullScreen:
            return NSWindow.didEnterFullScreenNotification
        case .willExitFullScreen:
            return NSWindow.willExitFullScreenNotification
        case .didExitFullScreen:
            return NSWindow.didExitFullScreenNotification
        case .willEnterVersionBrowser:
            return NSWindow.willEnterVersionBrowserNotification
        case .didEnterVersionBrowser:
            return NSWindow.didEnterVersionBrowserNotification
        case .willExitVersionBrowser:
            return NSWindow.willExitVersionBrowserNotification
        case .didExitVersionBrowser:
            return NSWindow.didExitVersionBrowserNotification
        case .didChangeOcclusionState:
            return NSWindow.didChangeOcclusionStateNotification
        }
    }
}

// MARK: - Window Event Observer Modifier

private struct WindowOnNotificationViewModifier: ViewModifier {
    let event: WindowEvent
    let onEvent: (NSWindow) -> Void

    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .bindWindow($window)
            .onReceive(NotificationCenter.default.publisher(for: event.notificationName)) { notification in
                // Only handle if notification is from the current window
                guard let notificationWindow = notification.object as? NSWindow,
                      let currentWindow = window,
                      notificationWindow === currentWindow else {
                    return
                }
                onEvent(notificationWindow)
            }
    }
}

// MARK: - View Extension

extension View {
    /// Observe a single NSWindow event
    /// - Parameters:
    ///   - event: WindowEvent to observe
    ///   - onEvent: Callback when event occurs, receives the window
    /// - Returns: Modified view with window event observation
    ///
    /// Example:
    /// ```swift
    /// SomeView()
    ///     .onWindowEvent(.didResize) { window in
    ///         print("Window resized: \(window.frame)")
    ///     }
    /// ```
    func onWindowEvent(
        _ event: WindowEvent,
        onEvent: @escaping (NSWindow) -> Void
    ) -> some View {
        modifier(WindowOnNotificationViewModifier(event: event, onEvent: onEvent))
    }
}

#endif
