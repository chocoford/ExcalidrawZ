//
//  PresentationControls.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct PresentationControls: View {
    let presentationTitle: String
    let slideTitle: String
    let selectedIndex: Int
    let slideCount: Int
    let showPrevious: () -> Void
    let showNext: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                titleContent

                divider

                Button(action: showPrevious) {
                    Image(systemSymbol: .chevronLeft)
                }
                .disabled(selectedIndex == 0)
                .modernButtonStyle(style: .glass, size: .regular, shape: .circle)

                Text("\(selectedIndex + 1) / \(slideCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 72)

                Button(action: showNext) {
                    Image(systemSymbol: .chevronRight)
                }
                .disabled(selectedIndex == slideCount - 1)
                .modernButtonStyle(style: .glass, size: .regular, shape: .circle)

                divider

                Button(action: dismiss) {
                    Image(systemSymbol: .xmark)
                }
                .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
            }
            .padding(8)
            .background {
                controlsBackground
            }
            .shadow(
                color: .black.opacity(0.45),
                radius: 14,
                y: 6
            )
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentationTitle)
                .font(.headline)
                .lineLimit(1)
            Text(slideTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: 240, alignment: .leading)
        .padding(.leading, 8)
    }

    private var divider: some View {
        Divider()
            .frame(height: 28)
            .overlay(Color.white.opacity(0.2))
    }

    @ViewBuilder
    private var controlsBackground: some View {
        let shape = Capsule()

        if #available(macOS 26.0, iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(
                    .regular.tint(Color.black.opacity(0.62)),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        Color.white.opacity(0.2),
                        lineWidth: 0.8
                    )
                }
        } else {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(Color.black.opacity(0.58))
                }
                .overlay {
                    shape.stroke(
                        Color.white.opacity(0.2),
                        lineWidth: 0.8
                    )
                }
        }
    }
}
