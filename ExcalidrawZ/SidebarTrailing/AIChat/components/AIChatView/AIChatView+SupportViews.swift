//
//  AIChatView+SupportViews.swift
//  ExcalidrawZ
//

import ChocofordUI
import SFSafeSymbols
import SwiftUI

/// Menu item that opens Settings via `@Environment(\.openSettings)` (macOS 14+
/// / iOS 17+) and writes the deep-link target into `SettingsRouter` first.
/// Lives in its own struct because the `openSettings` env value is gated to
/// macOS 14 — declaring it as a property on `AIChatView` (deployment target
/// is older) would compile-error.
@available(macOS 14.0, iOS 17.0, *)
struct OpenSettingsMenuItem: View {
    let deepLinkTo: SettingsView.Route
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Button {
            SettingsRouter.shared.pendingRoute = deepLinkTo
            openSettings()
        } label: {
            Label(.localizable(.generalButtonSettings), systemSymbol: .gearshape)
        }
    }
}

struct HiddenHistoryIndicator: View {
    let hiddenGroupCount: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemSymbol: .arrowUp)
                    .font(.caption2.weight(.semibold))
            }
            Text(
                localizable: isLoading
                ? .aiChatLoadingMoreText
                : .aiChatLoadMoreText(hiddenGroupCount)
            )
            .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct EditSessionBanner: View {
    let mode: AIChatState.EditSession.Mode
    let onCancel: () -> Void

    var title: String {
        switch mode {
            case .edit: String(localizable: .aiChatEditingMessageBannerText)
        }
    }

    var symbol: SFSymbol {
        switch mode {
            case .edit: .pencil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: symbol)
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Image(systemSymbol: .xmark)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(.generalButtonCancel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
