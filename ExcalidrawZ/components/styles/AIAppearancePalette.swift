//
//  AIAppearancePalette.swift
//  ExcalidrawZ
//
//  Created by Coding Assistant on 2026/5/8.
//

import SwiftUI

enum AIAppearancePalette {
    enum AccentRole {
        case starter
        case pro
        case max
    }

    enum Hue {
        static let cyan = 0.56
        static let blue = 0.62
        static let indigo = 0.64
        static let violet = 0.68
        static let purple = 0.78
        static let rose = 0.86
        static let pink = 0.90
        static let magenta = 0.92
    }

    static let thinkingGradient = LinearGradient(
        colors: [.purple, .pink, .orange, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let foregroundGradient = LinearGradient(
        colors: [.accentColor, .purple, .pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func planAccent(_ role: AccentRole) -> Color {
        switch role {
        case .starter:
            Color(hue: Hue.cyan, saturation: 1, brightness: 0.8)
        case .pro:
            Color(hue: Hue.indigo, saturation: 1, brightness: 0.8)
        case .max:
            Color(hue: Hue.rose, saturation: 1, brightness: 0.8)
        }
    }

    static func paywallBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.035, green: 0.04, blue: 0.065)
            : Color(red: 0.965, green: 0.975, blue: 1.0)
    }

    static func generatingPromptInputPalette(for colorScheme: ColorScheme) -> GeneratingPromptInputPalette {
        switch colorScheme {
        case .dark:
            GeneratingPromptInputPalette(
                gradientStops: [
                    Color(hue: Hue.cyan, saturation: 0.55, brightness: 1.00).opacity(0.42),
                    Color(hue: Hue.blue, saturation: 0.50, brightness: 1.00).opacity(0.80),
                    Color(hue: Hue.violet, saturation: 0.55, brightness: 1.00).opacity(0.74),
                    Color(hue: Hue.purple, saturation: 0.55, brightness: 1.00).opacity(0.66),
                    Color(hue: Hue.magenta, saturation: 0.55, brightness: 1.00).opacity(0.50),
                    Color(hue: Hue.cyan, saturation: 0.55, brightness: 1.00).opacity(0.42)
                ],
                borderOpacity: 0.85,
                innerGlowBase: 0.42,
                innerGlowPulse: 0.18,
                midGlowBase: 0.22,
                midGlowPulse: 0.14,
                haloColor: Color.accentColor,
                haloBase: 0.10,
                haloPulse: 0.08
            )
        default:
            GeneratingPromptInputPalette(
                gradientStops: [
                    Color(hue: Hue.cyan, saturation: 0.22, brightness: 1.00).opacity(0.55),
                    Color(hue: Hue.blue, saturation: 0.20, brightness: 1.00).opacity(0.98),
                    Color(hue: Hue.violet, saturation: 0.24, brightness: 1.00).opacity(0.94),
                    Color(hue: Hue.purple, saturation: 0.24, brightness: 1.00).opacity(0.86),
                    Color(hue: Hue.magenta, saturation: 0.22, brightness: 1.00).opacity(0.68),
                    Color(hue: Hue.cyan, saturation: 0.22, brightness: 1.00).opacity(0.55)
                ],
                borderOpacity: 0.95,
                innerGlowBase: 0.66,
                innerGlowPulse: 0.22,
                midGlowBase: 0.36,
                midGlowPulse: 0.16,
                haloColor: Color.white,
                haloBase: 0.18,
                haloPulse: 0.12
            )
        }
    }

    struct GeneratingPromptInputPalette {
        let gradientStops: [Color]
        let borderOpacity: Double
        let innerGlowBase: Double
        let innerGlowPulse: Double
        let midGlowBase: Double
        let midGlowPulse: Double
        let haloColor: Color
        let haloBase: Double
        let haloPulse: Double
    }
}
