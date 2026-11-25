//
//  AIChatIslandOverlay.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/05.
//

import SwiftUI
import ChocofordUI

struct AIChatIslandOverlay: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize

    @Environment(LayoutState.self) private var layoutState
    @Environment(FileState.self) private var fileState
    @Bindable private var aiChatPreferences = AIChatPreferences.shared

    let canvasSize: CGSize

    private var isCompactIOS: Bool {
#if os(iOS)
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
#else
        false
#endif
    }

    private var isVisible: Bool {
#if os(iOS)
        guard !isCompactIOS else { return false }
#endif
        return layoutState.isAIChatIslandMode &&
        AIChatAvailability.isAvailable &&
        aiChatPreferences.isAIEnabled &&
        !fileState.currentActiveFileIsInTrash
    }

    var body: some View {
        if isVisible {
            regularOverlay
        }
    }

    private var regularOverlay: some View {
        ZStack(alignment: .bottom) {
            AIChatIslandView(canvasSize: canvasSize)
                .padding(.bottom, 24)
                .transition(.scale.combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
