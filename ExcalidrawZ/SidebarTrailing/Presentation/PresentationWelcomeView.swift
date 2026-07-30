//
//  PresentationWelcomeView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct PresentationWelcomeView: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            hero
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            Button(action: onUpgrade) {
                Text(localizable: .presentationWelcomeButton)
                    .frame(maxWidth: .infinity)
            }
            .modernButtonStyle(
                style: .glassProminent,
                size: .extraLarge,
                shape: .modern
            )
            .padding(.horizontal, 20)

            Text(localizable: .presentationWelcomeButtonCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer(minLength: 28)
        }
        .background {
            background
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemSymbol: .rectangleStack)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(.tint.opacity(0.12), in: Circle())

            VStack(spacing: 7) {
                Text(localizable: .presentationWelcomeCaption)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(localizable: .presentationWelcomeTitle)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(localizable: .presentationWelcomeMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.12),
                Color.clear,
                Color.pink.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
