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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero

                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onUpgrade) {
                        Text(localizable: .presentationWelcomeButton)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .modernButtonStyle(
                        style: .glassProminent,
                        size: .extraLarge,
                        shape: .modern
                    )
                    .accessibilityIdentifier("presentationWelcomePrimaryAction")

                    Text(localizable: .presentationWelcomeButtonCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("presentationWelcomePlanCaption")
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("presentationWelcomeScrollView")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemSymbol: .rectangleStack)
                    .font(.title.weight(.medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(localizable: .presentationWelcomeTitle)
                    .font(.title2.weight(.semibold))
            }

            Text(localizable: .presentationWelcomeMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
