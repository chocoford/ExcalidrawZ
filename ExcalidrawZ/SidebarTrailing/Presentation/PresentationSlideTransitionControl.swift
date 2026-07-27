//
//  PresentationSlideTransitionControl.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct PresentationSlideTransitionControl: View {
    let transition: ExcalidrawPresentationConfiguration.Transition
    let duration: TimeInterval
    let isAddControlVisible: Bool
    let onTransitionChange: (
        ExcalidrawPresentationConfiguration.Transition
    ) -> Void
    let onDurationChange: (TimeInterval) -> Void
    let onDurationCommit: () -> Void

    @State private var isDurationPopoverPresented = false

    var body: some View {
        ZStack {
            if transition == .none {
                transitionMenu {
                    Image(systemSymbol: .plus)
                        .font(.caption.weight(.semibold))
                }
                .labelStyle(.iconOnly)
                .modernButtonStyle(
                    style: .glass,
                    size: .small,
                    shape: .circle
                )
                .opacity(isAddControlVisible ? 1 : 0)
                .scaleEffect(isAddControlVisible ? 1 : 0.8)
                .allowsHitTesting(isAddControlVisible)
            } else {
                configuredTransitionControls
            }
        }
        .frame(height: 34)
    }

    private var configuredTransitionControls: some View {
        HStack(spacing: 6) {
            transitionMenu {
                PresentationTransitionLabel(transition: transition)
                    .font(.caption)
            }
            .modernButtonStyle(
                style: .glass,
                size: .small,
                shape: .capsule
            )

            Button {
                isDurationPopoverPresented = true
            } label: {
                Text(durationText)
                    .font(.caption.monospacedDigit())
            }
            .modernButtonStyle(
                style: .glass,
                size: .small,
                shape: .capsule
            )
            .popover(
                isPresented: $isDurationPopoverPresented,
                arrowEdge: .bottom
            ) {
                durationPopover
            }
        }
    }

    private var durationText: String {
        String(
            localizable: .presentationTransitionDurationSeconds(
                Double(duration)
            )
        )
    }

    private var durationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizable: .presentationTransitionDuration)
                    .font(.headline)

                Spacer()

                Text(durationText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { duration },
                    set: onDurationChange
                ),
                in: 0.1 ... 3,
                step: 0.1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        onDurationCommit()
                    }
                }
            )
        }
        .padding(14)
        .frame(width: 240)
    }

    private func transitionMenu<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        Menu {
            ForEach(
                ExcalidrawPresentationConfiguration.Transition.allCases,
                id: \.self
            ) { transition in
                Button {
                    onTransitionChange(transition)
                } label: {
                    PresentationTransitionLabel(transition: transition)
                }
            }
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localizable: .presentationAddTransition))
    }
}

private struct PresentationTransitionLabel: View {
    let transition: ExcalidrawPresentationConfiguration.Transition

    var body: some View {
        switch transition {
            case .none:
                Label(
                    String(localizable: .presentationTransitionNone),
                    systemSymbol: .arrowRight
                )
            case .fade:
                Label(
                    String(localizable: .presentationTransitionFade),
                    systemSymbol: .circle
                )
            case .slide:
                Label(
                    String(localizable: .presentationTransitionSlide),
                    systemSymbol: .rectangleStack
                )
            case .zoom:
                Label(
                    String(localizable: .presentationTransitionZoom),
                    systemSymbol: .magnifyingglass
                )
        }
    }
}
