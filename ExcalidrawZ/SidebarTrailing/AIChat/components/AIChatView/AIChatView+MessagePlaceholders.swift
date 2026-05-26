//
//  AIChatView+MessagePlaceholders.swift
//  ExcalidrawZ
//

import SFSafeSymbols
import SwiftUI

extension AIChatView {
    @ViewBuilder
    func conversationLoadingPlaceholder() -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(localizable: .generalLoading)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    func emptyPlaceholder() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text(localizable: .aiChatEmptyContentPlaceholderTitle)
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Text(localizable: .aiChatEmptyContentPlaceholderDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
