//
//  ColorButton.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI
import ChocofordUI

/// A single color button component matching excalidraw's design
struct ColorButton: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let color: String
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void

    init(color: String, isSelected: Bool, size: CGFloat = 28, action: @escaping () -> Void) {
        self.color = color
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SwiftUI.Group {
                if color == "transparent" {
                    // Use checkboard pattern for transparent
                    transparentButton
                } else {
                    // Regular color button
                    colorButton
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var transparentButton: some View {
        if let imageData = Data(base64Encoded: ColorPalette.transparentPatternBase64),
           let platformImage = PlatformImage(data: imageData) {
            Image(platformImage: platformImage)
                .resizable(resizingMode: .tile)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // Fallback to clear color if image fails to load
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
                .frame(width: size, height: size)
        }
    }

    private var colorButton: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hexString: color))
            .frame(width: size, height: size)
            .apply { content in
                if colorScheme == .dark {
                    content
                        .colorInvert()
                        .hueRotation(Angle(degrees: 180))
                } else {
                    content
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            ColorButton(color: "#1e1e1e", isSelected: true) {}
            ColorButton(color: "#e03131", isSelected: false) {}
            ColorButton(color: "#2f9e44", isSelected: false) {}
            ColorButton(color: "transparent", isSelected: false) {}
        }

        HStack(spacing: 8) {
            ColorButton(color: "#ffc9c9", isSelected: false) {}
            ColorButton(color: "#b2f2bb", isSelected: true) {}
            ColorButton(color: "#a5d8ff", isSelected: false) {}
        }
    }
    .padding()
}
