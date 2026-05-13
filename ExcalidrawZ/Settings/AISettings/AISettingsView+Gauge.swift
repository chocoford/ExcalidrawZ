//
//  AISettingsView+Gauge.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI
import ChocofordUI

struct SemiCircularUsageGauge: View {
    let fraction: Double
    let percentageText: String
    let detailText: String

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SemiCircleShape()
                .stroke(
                    Color.secondary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            SemiCircleShape(progress: clampedFraction)
                .stroke(
                    AIAppearancePalette.foregroundGradient,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            VStack(alignment: .center, spacing: 2) {
                Text(percentageText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(AIAppearancePalette.foregroundGradient)
                    .monospacedDigit()
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(localizable: .settingsAIUsageGaugeAccessibilityLabel))
        .accessibilityValue(
            Text(localizable: .settingsAIUsageGaugeAccessibilityValue(percentageText, detailText))
        )
    }
}

private struct SemiCircleShape: Shape {
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * clampedProgress),
            clockwise: false
        )
        return path
    }
}

private struct AISettingsGlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    @MainActor @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                }
        }
    }
}

private struct AISettingsGlassCapsuleModifier: ViewModifier {
    let tint: Color
    let isInteractive: Bool
    let isProminent: Bool

    @MainActor @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            let glass = isProminent
            ? Glass.regular.tint(tint.opacity(0.22))
            : Glass.clear.tint(tint.opacity(0.08))
            if isInteractive {
                content.glassEffect(glass.interactive(), in: Capsule())
            } else {
                content.glassEffect(glass, in: Capsule())
            }
        } else {
            content
                .background {
                    Capsule()
                        .fill(tint.opacity(isProminent ? 0.16 : 0.08))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(isProminent ? 0.26 : 0.0))
                }
        }
    }
}

extension View {
    func aiSettingsGlassChip(cornerRadius: CGFloat) -> some View {
        modifier(AISettingsGlassChipModifier(cornerRadius: cornerRadius))
    }

    func aiSettingsGlassCapsule(
        tint: Color,
        isInteractive: Bool,
        isProminent: Bool = true
    ) -> some View {
        modifier(
            AISettingsGlassCapsuleModifier(
                tint: tint,
                isInteractive: isInteractive,
                isProminent: isProminent
            )
        )
    }
}
