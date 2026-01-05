//
//  DrawingSettingsPanel.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI

/// The main drawing settings panel that allows users to configure default drawing properties
/// This panel replicates excalidraw's settings interface
struct DrawingSettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var settings: UserDrawingSettings
    let onSettingsChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stroke Color
            SettingSection(title: "Stroke") {
                ColorButtonGroup(
                    colors: ColorPalette.strokeQuickPicks,
                    selectedColor: settings.currentItemStrokeColor ?? "#1e1e1e"
                ) { color in
                    settings.currentItemStrokeColor = color
                    onSettingsChange()
                }
            }
            
            // Background Color
            SettingSection(title: "Background") {
                ColorButtonGroup(
                    colors: ColorPalette.backgroundQuickPicks,
                    selectedColor: settings.currentItemBackgroundColor ?? "transparent"
                ) { color in
                    settings.currentItemBackgroundColor = color
                    onSettingsChange()
                }
            }
            
            // Fill Style
            if settings.currentItemBackgroundColor != "transparent" {
                SettingSection(title: "Fill") {
                    OptionButtonGroup(
                        options: [ExcalidrawFillStyle.hachure, ExcalidrawFillStyle.crossHatch, ExcalidrawFillStyle.solid],
                        selectedValue: settings.currentItemFillStyle ?? .solid
                    ) { value in
                        settings.currentItemFillStyle = value
                        onSettingsChange()
                    } label: { value in
                        switch value {
                            case .hachure:
                                Image("FillHachureIcon")
                                    .apply { content in
                                        if colorScheme == .dark {
                                            content.colorInvert()
                                        } else {
                                            content
                                        }
                                    }
                            case .crossHatch:
                                Image("FillCrossHatchIcon")
                                    .apply { content in
                                        if colorScheme == .dark {
                                            content.colorInvert()
                                        } else {
                                            content
                                        }
                                    }
                            case .solid:
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.primary)
                                    .padding(1)
                                    .frame(width: 20, height: 20)
                            case .zigzag:
                                Text("ZigZag")
                        }
                    }
                }
            }
            
            // Stroke Width
            SettingSection(title: "Stroke width") {
                StrokeWidthPicker(
                    widths: [1, 2, 4],
                    selectedWidth: settings.currentItemStrokeWidth ?? 2
                ) { width in
                    settings.currentItemStrokeWidth = width
                    onSettingsChange()
                }
            }
            
            // Stroke Style
            SettingSection(title: "Stroke style") {
                OptionButtonGroup(
                    options: [
                        ExcalidrawStrokeStyle.solid,
                        ExcalidrawStrokeStyle.dashed,
                        ExcalidrawStrokeStyle.dotted
                    ],
                    selectedValue: settings.currentItemStrokeStyle ?? .solid
                ) { value in
                    settings.currentItemStrokeStyle = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .solid:
                            Text("—")
                        case .dashed:
                            Text("- -")
                        case .dotted:
                            Text("· · ·")
                    }
                }
            }
            
            // Sloppiness (Roughness)
            SettingSection(title: "Sloppiness") {
                OptionButtonGroup(
                    options: [0.0, 1.0, 2.0],
                    selectedValue: settings.currentItemRoughness ?? 1
                ) { value in
                    settings.currentItemRoughness = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case 0.0:
                            SloppinessArchitectIcon()
                        case 1.0:
                            SloppinessArtistIcon()
                        case 2.0:
                            SloppinessCartoonistIcon()
                        default:
                            Text("\(Int(value))")
                    }
                }
            }
            
            // Edges (Roundness)
            SettingSection(title: "Edges") {
                OptionButtonGroup(
                    options: [
                        ExcalidrawStrokeSharpness.sharp,
                        ExcalidrawStrokeSharpness.round
                    ],
                    selectedValue: settings.currentItemRoundness ?? .round
                ) { value in
                    settings.currentItemRoundness = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .sharp:
                            Image("EdgeSharpIcon")
                                .apply { content in
                                    if colorScheme == .dark {
                                        content.colorInvert()
                                    } else {
                                        content
                                    }
                                }
                        case .round:
                            Image("EdgeRoundIcon")
                                .apply { content in
                                    if colorScheme == .dark {
                                        content.colorInvert()
                                    } else {
                                        content
                                    }
                                }
                    }
                }
            }
            
            // Opacity
            SettingSection(title: "Opacity") {
                OpacitySlider(
                    opacity: Binding(
                        get: { settings.currentItemOpacity ?? 100 },
                        set: { newValue in
                            settings.currentItemOpacity = Double(Int(newValue))
                        }
                    ),
                    onEditingChanged: { editing in
                        // Only trigger settings change when user stops dragging
                        if !editing {
                            onSettingsChange()
                        }
                    }
                )
            }
        }
        .animation(
            .smooth,
            value: settings.currentItemBackgroundColor != "transparent"
        )
    }
}

// MARK: - Setting Section

/// A reusable section component for settings
private struct SettingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            content()
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var settings = UserDrawingSettings()
        
        var body: some View {
            ScrollView {
                DrawingSettingsPanel(settings: $settings) {
                    print("Settings changed: \(settings)")
                }
                .padding(12)
                .frame(width: 260)
            }
        }
    }
    
    return PreviewWrapper()
}
