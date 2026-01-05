//
//  StrokeWidthPicker.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI

/// A visual stroke width picker with preview of the line thickness
struct StrokeWidthButton: View {
    let width: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Spacer()
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 20, height: CGFloat(width * 1))
                Spacer()
            }
            .frame(width: 28, height: 28)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A group of stroke width buttons
struct StrokeWidthPicker: View {
    let widths: [Double]
    let selectedWidth: Double
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(widths, id: \.self) { width in
                StrokeWidthButton(
                    width: width,
                    isSelected: selectedWidth == width
                ) {
                    onSelect(width)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stroke Width")
                .font(.subheadline)
                .fontWeight(.medium)

            StrokeWidthPicker(
                widths: [1, 2, 4],
                selectedWidth: 2
            ) { width in
                print("Selected width: \(width)")
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Widths")
                .font(.subheadline)
                .fontWeight(.medium)

            StrokeWidthPicker(
                widths: [0.5, 1, 2, 3, 4, 5],
                selectedWidth: 3
            ) { width in
                print("Selected width: \(width)")
            }
        }
    }
    .padding()
}
