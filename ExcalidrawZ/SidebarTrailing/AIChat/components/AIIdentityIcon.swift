//
//  AIIdentityIcon.swift
//  ExcalidrawZ
//

import SwiftUI
import SFSafeSymbols

struct AIIdentityIcon: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.36),
                            Color.purple.opacity(0.24),
                            Color.pink.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: glowBlur)

            ZStack {
                Circle()
                    .fill(.regularMaterial)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.68),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )

                Image(systemSymbol: .sparkles)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(AIAppearancePalette.foregroundGradient)
            }
            .frame(width: size, height: size)
        }
        .shadow(color: .accentColor.opacity(0.12), radius: shadowRadius, y: shadowYOffset)
        .accessibilityLabel(Text(verbatim: "AI"))
    }

    private var glowSize: CGFloat {
        size * 82 / 64
    }

    private var glowBlur: CGFloat {
        size * 22 / 64
    }

    private var symbolSize: CGFloat {
        size * 28 / 64
    }

    private var shadowRadius: CGFloat {
        size * 30 / 64
    }

    private var shadowYOffset: CGFloat {
        size * 18 / 64
    }
}
