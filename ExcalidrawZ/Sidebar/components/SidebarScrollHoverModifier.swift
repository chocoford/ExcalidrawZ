//
//  SidebarScrollHoverModifier.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI

private struct SidebarHoverSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SidebarHoverAnimationsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var sidebarHoverSuppressed: Bool {
        get { self[SidebarHoverSuppressedKey.self] }
        set { self[SidebarHoverSuppressedKey.self] = newValue }
    }

    var sidebarHoverAnimationsEnabled: Bool {
        get { self[SidebarHoverAnimationsEnabledKey.self] }
        set { self[SidebarHoverAnimationsEnabledKey.self] = newValue }
    }
}

private struct SidebarScrollHoverModifier: ViewModifier {
    @Environment(\.sidebarHoverSuppressed) private var parentSuppressed
    @Environment(\.sidebarHoverAnimationsEnabled) private var animationsEnabled
    @State private var isScrolling = false

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if #available(macOS 15.0, *) {
            content
                .environment(\.sidebarHoverSuppressed, parentSuppressed || isScrolling)
                .environment(\.sidebarHoverAnimationsEnabled, animationsEnabled && !isScrolling)
                .onScrollPhaseChange { _, phase in
                    setScrolling(phase != .idle)
                }
                .onDisappear {
                    setScrolling(false)
                }
        } else {
            // Older systems have no SwiftUI scroll-phase callback.
            content.environment(\.sidebarHoverAnimationsEnabled, false)
        }
#else
        content
#endif
    }

    private func setScrolling(_ value: Bool) {
        guard isScrolling != value else { return }
        var transaction = Transaction()
        // Clear hover immediately, then allow its animation to resume at idle.
        transaction.disablesAnimations = value
        withTransaction(transaction) {
            isScrolling = value
        }
    }
}

@MainActor
private final class SidebarPointerHoverState {
    var isInside = false
}

private struct SidebarHoverTrackingModifier: ViewModifier {
    @Environment(\.sidebarHoverSuppressed) private var hoverSuppressed
    @Environment(\.sidebarHoverAnimationsEnabled) private var animationsEnabled
    @Binding var isHovered: Bool
    @State private var pointer = SidebarPointerHoverState()

    func body(content: Content) -> some View {
        content
            .onHover { hovered in
                // Keep the final pointer position without publishing each row
                // crossed during scrolling. Restore only that row at idle.
                pointer.isInside = hovered
                guard !hoverSuppressed else { return }
                updateHovered(hovered)
            }
            .watch(value: hoverSuppressed) { _, suppressed in
                updateHovered(!suppressed && pointer.isInside)
            }
            .onDisappear {
                pointer.isInside = false
                updateHovered(false, animated: false)
            }
    }

    private func updateHovered(_ hovered: Bool, animated: Bool = true) {
        guard isHovered != hovered else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = !animated || hoverSuppressed || !animationsEnabled
        withTransaction(transaction) {
            isHovered = hovered
        }
    }
}

extension View {
    /// Attach to the ScrollView that owns the sidebar rows.
    func suppressSidebarHoverWhileScrolling() -> some View {
        modifier(SidebarScrollHoverModifier())
    }

    func trackSidebarHover(_ isHovered: Binding<Bool>) -> some View {
        modifier(SidebarHoverTrackingModifier(isHovered: isHovered))
    }
}
