//
//  ColorButtonGroup.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI
import ChocofordUI

/// A horizontal group of color buttons with quick picks and full color picker
struct ColorButtonGroup: View {
    @Environment(\.colorScheme) var colorScheme

    let colors: [String]
    let selectedColor: String
    let onSelect: (String) -> Void
    @State private var showFullPicker = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Quick pick colors
            ForEach(colors, id: \.self) { color in
                ColorButton(
                    color: color,
                    isSelected: selectedColor == color
                ) {
                    onSelect(color)
                }
            }
            
            // Divider
            Divider()
                .frame(height: 28)
            
            // Trigger button for full color picker
            Button(action: {
                showFullPicker.toggle()
            }) {
                ZStack {
                    if selectedColor == "transparent" {
                        // Transparent pattern background
                        if let imageData = Data(base64Encoded: ColorPalette.transparentPatternBase64),
                           let platformImage = PlatformImage(data: imageData) {
                            Image(platformImage: platformImage)
                                .resizable(resizingMode: .tile)
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
                    } else {
                        // Solid color background
                        Color(hexString: selectedColor)
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
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            showFullPicker ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: showFullPicker ? 2 : 1
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFullPicker) {
                ColorPickerWithFooter(
                    selectedColor: selectedColor,
                    onSelect: onSelect
                )
            }
        }
    }
}

// MARK: - Color Picker with Footer

/// Full color picker with hex input and native color picker
private struct ColorPickerWithFooter: View {
    let selectedColor: String
    let onSelect: (String) -> Void

    @State private var hexInput: String = ""
    @State private var nativeColor: Color = .black
    @State private var isUpdatingFromExternal: Bool = false

    var body: some View {
        FullColorPicker(selectedColor: selectedColor) { color in
            onSelect(color)
            updateStateFromHex(color)
        } footer: {
            VStack(spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    // Hex input field
                    TextField("#", text: $hexInput)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 28)
                        .padding(.horizontal, 8)
#if os(macOS)
                        .background(Color(nsColor: .controlBackgroundColor))
#else
                        .background(Color(.systemGray6))
#endif
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .onSubmit {
                            applyHexInput()
                        }

                    // Native color picker
                    ColorPicker("", selection: $nativeColor)
                        .labelsHidden()
                        .frame(width: 28, height: 28)
                        .watch(value: nativeColor) { oldValue, newValue in
                            // Only trigger onSelect if user is actually picking a color
                            // (not when we're updating from external source)
                            if !isUpdatingFromExternal {
                                let hexColor = newValue.toHexString()
                                onSelect(hexColor)
                                hexInput = hexColor
                            }
                        }
                }
            }
        }
        .onAppear {
            updateStateFromHex(selectedColor)
        }
        .watch(value: selectedColor) { oldValue, newValue in
            updateStateFromHex(newValue)
        }
    }

    private func updateStateFromHex(_ hex: String) {
        isUpdatingFromExternal = true
        hexInput = hex
        nativeColor = Color(hexString: hex)
        // Reset flag after a short delay to allow the watch callback to complete
        DispatchQueue.main.async {
            isUpdatingFromExternal = false
        }
    }

    private func applyHexInput() {
        var cleanedHex = hexInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedHex.hasPrefix("#") {
            cleanedHex = "#" + cleanedHex
        }

        // Validate hex format
        let hexPattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$"
        if let regex = try? NSRegularExpression(pattern: hexPattern),
           regex.firstMatch(in: cleanedHex, range: NSRange(cleanedHex.startIndex..., in: cleanedHex)) != nil {
            onSelect(cleanedHex)
            isUpdatingFromExternal = true
            nativeColor = Color(hexString: cleanedHex)
            DispatchQueue.main.async {
                isUpdatingFromExternal = false
            }
        } else {
            // Invalid hex, revert to current color
            hexInput = selectedColor
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Convert Color to hex string
    func toHexString() -> String {
#if os(macOS)
        guard let rgbColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
#else
        guard let components = UIColor(self).cgColor.components else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
#endif
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stroke Colors")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ColorButtonGroup(
                colors: ColorPalette.strokeQuickPicks,
                selectedColor: "#e03131"
            ) { color in
                print("Selected stroke color: \(color)")
            }
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Background Colors")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ColorButtonGroup(
                colors: ColorPalette.backgroundQuickPicks,
                selectedColor: "transparent"
            ) { color in
                print("Selected background color: \(color)")
            }
        }
    }
    .padding()
}
