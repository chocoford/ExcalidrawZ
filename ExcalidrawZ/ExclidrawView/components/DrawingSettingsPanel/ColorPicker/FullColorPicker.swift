//
//  FullColorPicker.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI
import ChocofordUI

/// Full color picker popover showing all color families and shades
struct FullColorPicker: View {
    var selectedColor: String
    var onSelect: (String) -> Void
    var footer: AnyView
    
    init<Content: View>(
        selectedColor: String,
        onSelect: @escaping (String) -> Void,
        @ViewBuilder footer: () -> Content = { EmptyView() }
    ) {
        self.selectedColor = selectedColor
        self.onSelect = onSelect
        self.footer = AnyView(footer())
    }

    @State private var selectedColorFamily: (name: String, shades: [String])?


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Base Colors Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Colors")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                baseColorsGrid
            }

            // Shades List (if a color family is selected)
            if let colorFamily = selectedColorFamily, colorFamily.shades.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shades")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    shadesGrid(for: colorFamily)
                }
            }
            
            footer
        }
        .padding(12)
        .frame(width: 220)
        .onAppear {
            // Pre-select the color family of the current color
            selectedColorFamily = ColorPalette.fullPalette.first { family in
                family.shades.contains(selectedColor)
            }
        }
    }

    // MARK: - Base Colors Grid

    @ViewBuilder
    private var baseColorsGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 5)

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ColorPalette.fullPalette.indices, id: \.self) { index in
                let colorFamily = ColorPalette.fullPalette[index]
                let baseColor = ColorPalette.getBaseColor(for: colorFamily)

                ColorButton(
                    color: baseColor,
                    isSelected: selectedColor == baseColor,
                    size: 30
                ) {
                    selectedColorFamily = colorFamily
                    onSelect(baseColor)
                }
            }
        }
    }

    // MARK: - Shades Grid

    @ViewBuilder
    private func shadesGrid(for colorFamily: (name: String, shades: [String])) -> some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 5)

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(colorFamily.shades.indices, id: \.self) { index in
                let shade = colorFamily.shades[index]

                ColorButton(
                    color: shade,
                    isSelected: selectedColor == shade,
                    size: 30
                ) {
                    onSelect(shade)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedColor = "#e03131"
        @State private var showPicker = false

        var body: some View {
            VStack(spacing: 20) {
                Button("Show Color Picker") {
                    showPicker.toggle()
                }

                Text("Selected: \(selectedColor)")
                    .font(.caption)

                Rectangle()
                    .fill(Color(hexString: selectedColor))
                    .frame(width: 100, height: 100)
            }
            .padding()
            .popover(isPresented: $showPicker) {
                FullColorPicker(selectedColor: selectedColor) { color in
                    selectedColor = color
                }
            }
        }
    }

    return PreviewWrapper()
}
