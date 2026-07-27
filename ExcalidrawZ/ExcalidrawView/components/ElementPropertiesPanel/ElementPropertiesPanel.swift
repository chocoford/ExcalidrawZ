//
//  ElementPropertiesPanel.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/25.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ChocofordUI
import SwiftUI

struct ElementPropertiesPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var properties: ElementProperties
    @Binding var isPopoverPresented: Bool
    let context: ElementPropertiesContext
    let onChange: () -> Void

    @State private var presentedControl: Control?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(availableControls) { control in
                Button {
                    setPresentedControl(control)
                } label: {
                    controlLabel(control)
                        .frame(width: 20, height: 20)
                }
                .help(control.title)
                .modernButtonStyle(
                    style: presentedControl == control ? .glassProminent : .glass,
                    size: .regular,
                    shape: .circle
                )
                .popover(
                    isPresented: popoverBinding(for: control),
                    arrowEdge: .bottom
                ) {
                    options(for: control)
                        .padding(12)
                }
            }
        }
        .padding(8)
        .background {
            panelBackground
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
        .watch(value: context) { _, _ in
            setPresentedControl(nil)
        }
        .watch(value: isPopoverPresented) { _, isPresented in
            if !isPresented, presentedControl != nil {
                presentedControl = nil
            }
        }
        .onDisappear {
            isPopoverPresented = false
        }
    }

    @ViewBuilder
    private func options(for control: Control) -> some View {
        switch control {
            case .strokeColor:
                colorOptions(
                    colors: ColorPalette.strokeQuickPicks,
                    selectedColor: properties.strokeColor
                        ?? ElementProperties.Defaults.strokeColor,
                    opacity: properties.opacity
                        ?? ElementProperties.Defaults.opacity
                ) { color, opacity in
                    properties.strokeColor = color
                    if let opacity {
                        properties.opacity = opacity
                    }
                    onChange()
                }
            case .backgroundColor:
                colorOptions(
                    colors: ColorPalette.backgroundQuickPicks,
                    selectedColor: properties.backgroundColor
                        ?? ElementProperties.Defaults.backgroundColor,
                    opacity: properties.opacity
                        ?? ElementProperties.Defaults.opacity
                ) { color, opacity in
                    properties.backgroundColor = color
                    if let opacity {
                        properties.opacity = opacity
                    }
                    onChange()
                }
            case .fillStyle:
                optionRow(
                    values: [
                        ExcalidrawFillStyle.hachure,
                        .crossHatch,
                        .solid,
                    ],
                    selectedValue: properties.fillStyle
                        ?? ElementProperties.Defaults.fillStyle
                ) { fillStyle in
                    properties.fillStyle = fillStyle
                    onChange()
                } label: { fillStyle in
                    fillStyleIcon(fillStyle)
                }
            case .strokeWidth:
                optionRow(
                    values: [1.0, 2.0, 4.0],
                    selectedValue: properties.strokeWidth
                        ?? ElementProperties.Defaults.strokeWidth
                ) { width in
                    properties.setStrokeWidth(width)
                    onChange()
                } label: { width in
                    Capsule()
                        .fill(.primary)
                        .frame(width: 22, height: max(1, width))
                }
            case .strokeStyle:
                optionRow(
                    values: [
                        ExcalidrawStrokeStyle.solid,
                        .dashed,
                        .dotted,
                    ],
                    selectedValue: properties.strokeStyle
                        ?? ElementProperties.Defaults.strokeStyle
                ) { style in
                    properties.strokeStyle = style
                    onChange()
                } label: { style in
                    ElementPropertyLinePreview(style: style)
                }
            case .roughness:
                optionRow(
                    values: [0.0, 1.0, 2.0],
                    selectedValue: properties.roughness
                        ?? ElementProperties.Defaults.roughness
                ) { roughness in
                    properties.roughness = roughness
                    onChange()
                } label: { roughness in
                    roughnessIcon(roughness)
                }
            case .roundness:
                optionRow(
                    values: [
                        ExcalidrawStrokeSharpness.sharp,
                        .round,
                    ],
                    selectedValue: properties.roundness
                        ?? ElementProperties.Defaults.roundness
                ) { roundness in
                    properties.roundness = roundness
                    onChange()
                } label: { roundness in
                    roundnessIcon(roundness)
                }
            case .arrowType:
                optionRow(
                    values: [
                        UserDrawingSettings.ArrowType.sharp,
                        .round,
                        .elbow,
                    ],
                    selectedValue: properties.arrowType
                        ?? ElementProperties.Defaults.arrowType
                ) { arrowType in
                    properties.arrowType = arrowType
                    onChange()
                } label: { arrowType in
                    arrowTypeIcon(arrowType)
                }
            case .startArrowhead:
                arrowheadOptions(direction: .start)
            case .endArrowhead:
                arrowheadOptions(direction: .end)
            case .strokeVariability:
                optionRow(
                    values: [
                        ElementProperties.StrokeVariability.constant,
                        .variable,
                    ],
                    selectedValue: properties.strokeVariability
                        ?? ElementProperties.Defaults.strokeVariability
                ) { variability in
                    properties.strokeVariability = variability
                    onChange()
                } label: { variability in
                    strokeVariabilityIcon(variability)
                }
            case .fontFamily:
                optionRow(
                    values: [
                        ElementProperties.FontFamily.handDrawn,
                        .normal,
                        .code,
                    ],
                    selectedValue: properties.fontFamily
                        ?? ElementProperties.Defaults.fontFamily
                ) { fontFamily in
                    properties.fontFamily = fontFamily
                    onChange()
                } label: { fontFamily in
                    switch fontFamily {
                        case .handDrawn:
                            Image(systemName: "pencil")
                        case .normal:
                            Image(systemName: "textformat")
                        case .code:
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
            case .fontSize:
                optionRow(
                    values: [16.0, 20.0, 28.0, 36.0],
                    selectedValue: properties.fontSize
                        ?? ElementProperties.Defaults.fontSize
                ) { fontSize in
                    properties.fontSize = fontSize
                    onChange()
                } label: { fontSize in
                    Text(fontSize.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                }
            case .textAlign:
                optionRow(
                    values: ["left", "center", "right"],
                    selectedValue: properties.textAlign
                        ?? ElementProperties.Defaults.textAlign
                ) { alignment in
                    properties.textAlign = alignment
                    onChange()
                } label: { alignment in
                    Image(systemName: "text.align\(alignment)")
                }
            case .opacity:
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { properties.opacity ?? 100 },
                            set: { properties.opacity = Double(Int($0)) }
                        ),
                        in: 0...100,
                        onEditingChanged: { editing in
                            if !editing {
                                onChange()
                            }
                        }
                    )
                    Text("\(Int(properties.opacity ?? 100))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .frame(width: 220)
        }
    }

    private func colorOptions(
        colors: [String],
        selectedColor: String,
        opacity: Double,
        onSelect: @escaping (String, Double?) -> Void
    ) -> some View {
        ElementPropertyColorOptions(
            colors: colors,
            selectedColor: selectedColor,
            opacity: opacity,
            onSelect: onSelect
        )
    }

    private func optionRow<Value: Hashable, Label: View>(
        values: [Value],
        selectedValue: Value,
        onSelect: @escaping (Value) -> Void,
        @ViewBuilder label: @escaping (Value) -> Label
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    label(value)
                        .frame(width: 28, height: 28)
                }
                .modernButtonStyle(
                    style: selectedValue == value ? .glassProminent : .glass,
                    size: .regular,
                    shape: .circle
                )
            }
        }
    }

    @ViewBuilder
    private func controlLabel(_ control: Control) -> some View {
        switch control {
            case .strokeColor:
                colorSwatch(
                    properties.strokeColor
                        ?? ElementProperties.Defaults.strokeColor,
                    isSelected: false,
                    size: 16
                )
            case .backgroundColor:
                colorSwatch(
                    properties.backgroundColor
                        ?? ElementProperties.Defaults.backgroundColor,
                    isSelected: false,
                    size: 16
                )
            case .fillStyle:
                fillStyleIcon(
                    properties.fillStyle
                        ?? ElementProperties.Defaults.fillStyle
                )
            case .strokeWidth:
                Capsule()
                    .fill(.primary)
                    .frame(
                        width: 20,
                        height: properties.strokeWidth
                            ?? ElementProperties.Defaults.strokeWidth
                    )
            case .strokeStyle:
                ElementPropertyLinePreview(
                    style: properties.strokeStyle
                        ?? ElementProperties.Defaults.strokeStyle
                )
            case .roughness:
                roughnessIcon(
                    properties.roughness
                        ?? ElementProperties.Defaults.roughness
                )
            case .roundness:
                roundnessIcon(
                    properties.roundness
                        ?? ElementProperties.Defaults.roundness
                )
            case .arrowType:
                arrowTypeIcon(
                    properties.arrowType
                        ?? ElementProperties.Defaults.arrowType
                )
            case .startArrowhead:
                arrowheadIcon(
                    properties.startArrowhead
                        ?? ElementProperties.Defaults.startArrowhead
                )
            case .endArrowhead:
                arrowheadIcon(
                    properties.endArrowhead
                        ?? ElementProperties.Defaults.endArrowhead
                )
                .scaleEffect(x: -1)
            case .strokeVariability:
                strokeVariabilityIcon(
                    properties.strokeVariability
                        ?? ElementProperties.Defaults.strokeVariability
                )
            case .fontFamily:
                Image(systemName: "textformat")
            case .fontSize:
                Image(systemName: "textformat.size")
            case .textAlign:
                Image(systemName: "text.alignleft")
            case .opacity:
                Image(systemName: "circle.lefthalf.filled")
        }
    }

    private var availableControls: [Control] {
        switch context {
            case .shape:
                [
                    .strokeColor,
                    .backgroundColor,
                    .fillStyle,
                    .strokeWidth,
                    .strokeStyle,
                    .roughness,
                    .roundness,
                    .opacity,
                ]
            case .shapeWithText:
                [
                    .strokeColor,
                    .backgroundColor,
                    .fillStyle,
                    .strokeWidth,
                    .strokeStyle,
                    .roughness,
                    .roundness,
                    .fontFamily,
                    .fontSize,
                    .textAlign,
                    .opacity,
                ]
            case .text:
                [
                    .strokeColor,
                    .fontFamily,
                    .fontSize,
                    .textAlign,
                    .opacity,
                ]
            case .freedraw:
                [
                    .strokeColor,
                    .strokeWidth,
                    .strokeVariability,
                    .opacity,
                ]
            case .arrow:
                [
                    .strokeColor,
                    .strokeWidth,
                    .strokeStyle,
                    .roughness,
                    .arrowType,
                    .startArrowhead,
                    .endArrowhead,
                    .opacity,
                ]
            case .arrowWithText:
                [
                    .strokeColor,
                    .strokeWidth,
                    .strokeStyle,
                    .roughness,
                    .arrowType,
                    .startArrowhead,
                    .endArrowhead,
                    .fontFamily,
                    .fontSize,
                    .textAlign,
                    .opacity,
                ]
            case .mixed:
                [
                    .strokeColor,
                    .strokeWidth,
                    .strokeStyle,
                    .opacity,
                ]
            case .mixedWithText:
                [
                    .strokeColor,
                    .strokeWidth,
                    .strokeStyle,
                    .fontFamily,
                    .fontSize,
                    .textAlign,
                    .opacity,
                ]
            case .media:
                [.opacity]
        }
    }

    private func popoverBinding(for control: Control) -> Binding<Bool> {
        Binding {
            presentedControl == control
        } set: { isPresented in
            setPresentedControl(isPresented ? control : nil)
        }
    }

    private func setPresentedControl(_ control: Control?) {
        presentedControl = control
        isPopoverPresented = control != nil
    }

    private func displayColor(_ hex: String) -> Color {
        if hex == "transparent" {
            return .clear
        }
        return Color(hexString: hex)
    }

    private func colorSwatch(
        _ hex: String,
        isSelected: Bool,
        size: CGFloat
    ) -> some View {
        Circle()
            .fill(displayColor(hex))
            .frame(width: size, height: size)
            .overlay {
                if hex == "transparent" {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: size * 0.72, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor
                            : Color.primary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
    }

    @ViewBuilder
    private func fillStyleIcon(_ style: ExcalidrawFillStyle) -> some View {
        switch style {
            case .hachure:
                Image("FillHachureIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .applyIconColorScheme(colorScheme)
            case .crossHatch:
                Image("FillCrossHatchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .applyIconColorScheme(colorScheme)
            case .solid:
                RoundedRectangle(cornerRadius: 5)
                    .fill(.primary)
                    .frame(width: 18, height: 18)
            case .zigzag:
                Image(systemName: "waveform.path")
        }
    }

    @ViewBuilder
    private func roughnessIcon(_ roughness: Double) -> some View {
        switch roughness {
            case 0:
                SloppinessArchitectIcon()
            case 1:
                SloppinessArtistIcon()
            default:
                SloppinessCartoonistIcon()
        }
    }

    @ViewBuilder
    private func roundnessIcon(
        _ roundness: ExcalidrawStrokeSharpness
    ) -> some View {
        Image(roundness == .round ? "EdgeRoundIcon" : "EdgeSharpIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .applyIconColorScheme(colorScheme)
    }

    @ViewBuilder
    private func strokeVariabilityIcon(
        _ variability: ElementProperties.StrokeVariability
    ) -> some View {
        switch variability {
            case .constant:
                StrokeVariabilityConstantIcon()
            case .variable:
                StrokeVariabilityVariableIcon()
        }
    }

    @ViewBuilder
    private func arrowTypeIcon(
        _ arrowType: UserDrawingSettings.ArrowType
    ) -> some View {
        switch arrowType {
            case .sharp:
                Image(systemName: "arrow.up.right")
            case .round:
                Image(systemName: "arrow.turn.up.right")
            case .elbow:
                if #available(macOS 15.0, iOS 18.0, *) {
                    Image(systemName: "arrow.trianglehead.swap")
                } else {
                    Image(systemName: "arrow.triangle.swap")
                }
        }
    }

    private enum ArrowheadDirection {
        case start
        case end
    }

    private var arrowheadValues: [Nullable<Arrowhead>] {
        [
            .null,
            .value(.arrow),
            .value(.bar),
            .value(.triangle),
            .value(.diamond),
            .value(.circle),
            .value(.circleOutline),
            .value(.triangleOutline),
            .value(.diamondOutline),
            .value(.cardinalityOne),
            .value(.cardinalityMany),
            .value(.cardinalityOneOrMany),
            .value(.cardinalityExactlyOne),
            .value(.cardinalityZeroOrOne),
            .value(.cardinalityZeroOrMany),
        ]
    }

    private func arrowheadOptions(
        direction: ArrowheadDirection
    ) -> some View {
        let selected = direction == .start
            ? properties.startArrowhead
                ?? ElementProperties.Defaults.startArrowhead
            : properties.endArrowhead
                ?? ElementProperties.Defaults.endArrowhead

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(32), spacing: 5),
                count: 5
            ),
            spacing: 5
        ) {
            ForEach(arrowheadValues.indices, id: \.self) { index in
                let arrowhead = arrowheadValues[index]
                Button {
                    if direction == .start {
                        properties.startArrowhead = arrowhead
                    } else {
                        properties.endArrowhead = arrowhead
                    }
                    onChange()
                } label: {
                    arrowheadIcon(arrowhead)
                        .scaleEffect(x: direction == .end ? -1 : 1)
                        .frame(width: 20, height: 20)
                }
                .modernButtonStyle(
                    style: selected == arrowhead
                        ? .glassProminent
                        : .glass,
                    size: .regular,
                    shape: .circle
                )
            }
        }
        .frame(width: 180)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
        }
    }

    private enum Control: String, CaseIterable, Identifiable {
        case strokeColor
        case backgroundColor
        case fillStyle
        case strokeWidth
        case strokeStyle
        case roughness
        case roundness
        case arrowType
        case startArrowhead
        case endArrowhead
        case strokeVariability
        case fontFamily
        case fontSize
        case textAlign
        case opacity

        var id: Self { self }

        var title: String {
            switch self {
                case .strokeColor:
                    String(localizable: .settingsExcalidrawDrawingSettingsStrokeTitle)
                case .backgroundColor:
                    String(localizable: .settingsExcalidrawDrawingSettingsBackgroundTitle)
                case .fillStyle:
                    String(localizable: .settingsExcalidrawDrawingSettingsFillTitle)
                case .strokeWidth:
                    String(localizable: .settingsExcalidrawDrawingSettingsStrokeWidthTitle)
                case .strokeStyle:
                    String(localizable: .settingsExcalidrawDrawingSettingsStrokeStyleTitle)
                case .roughness:
                    String(localizable: .settingsExcalidrawDrawingSettingsSloppinessTitle)
                case .roundness:
                    String(localizable: .settingsExcalidrawDrawingSettingsEdgeTitle)
                case .arrowType:
                    String(localizable: .settingsExcalidrawDrawingSettingsStartArrowTypeTitle)
                case .startArrowhead:
                    String(localizable: .settingsExcalidrawDrawingSettingsStartArrowheadTitle)
                case .endArrowhead:
                    String(localizable: .settingsExcalidrawDrawingSettingsStartArrowheadTitle)
                case .strokeVariability:
                    String(localizable: .settingsExcalidrawDrawingSettingsPressureTitle)
                case .fontFamily:
                    String(localizable: .settingsExcalidrawDrawingSettingsFontFamilyTitle)
                case .fontSize:
                    String(localizable: .settingsExcalidrawDrawingSettingsFontSizeTitle)
                case .textAlign:
                    String(localizable: .settingsExcalidrawDrawingSettingsTextAlignTitle)
                case .opacity:
                    String(localizable: .settingsExcalidrawDrawingSettingsOpacityTitle)
            }
        }
    }
}

private struct ElementPropertyColorOptions: View {
    let colors: [String]
    let selectedColor: String
    let opacity: Double
    let onSelect: (String, Double?) -> Void

    @State private var spectrumColor: Color
    @State private var isSpectrumPickerPresented = false

    init(
        colors: [String],
        selectedColor: String,
        opacity: Double,
        onSelect: @escaping (String, Double?) -> Void
    ) {
        self.colors = colors
        self.selectedColor = selectedColor
        self.opacity = opacity
        self.onSelect = onSelect
        _spectrumColor = State(
            initialValue: Self.swiftUIColor(
                from: selectedColor,
                opacity: opacity
            )
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(colors, id: \.self) { color in
                Button {
                    onSelect(color, nil)
                } label: {
                    ElementPropertyColorSwatch(
                        color: color,
                        isSelected: selectedColor == color,
                        size: 25
                    )
                    .padding(2)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 25)

            Button {
                isSpectrumPickerPresented = true
            } label: {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                .red,
                                .yellow,
                                .green,
                                .cyan,
                                .blue,
                                .purple,
                                .red,
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 25, height: 25)
                    .overlay {
                        Circle()
                            .strokeBorder(.primary.opacity(0.18))
                    }
                    .padding(2)
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isSpectrumPickerPresented,
                arrowEdge: .bottom
            ) {
                SpectrumColorPicker(
                    selection: Binding(
                        get: { spectrumColor },
                        set: { color in
                            spectrumColor = color
                            onSelect(
                                color.toHexString(),
                                Self.opacity(from: color) * 100
                            )
                        }
                    ),
                    showsOpacity: true,
                    onConfirm: {
                        isSpectrumPickerPresented = false
                    }
                )
                .padding(12)
            }
        }
        .watch(
            value: SelectionValue(color: selectedColor, opacity: opacity)
        ) { _, value in
            spectrumColor = Self.swiftUIColor(
                from: value.color,
                opacity: value.opacity
            )
        }
    }

    private static func swiftUIColor(
        from value: String,
        opacity: Double
    ) -> Color {
        let color = value == "transparent" ? Color.white : Color(hexString: value)
        return color.opacity(min(max(opacity / 100, 0), 1))
    }

    private static func opacity(from color: Color) -> Double {
#if os(macOS)
        NSColor(color).alphaComponent
#else
        UIColor(color).cgColor.alpha
#endif
    }

    private struct SelectionValue: Equatable {
        let color: String
        let opacity: Double
    }
}

private struct ElementPropertyColorSwatch: View {
    let color: String
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color == "transparent" ? .clear : Color(hexString: color))
            .frame(width: size, height: size)
            .overlay {
                if color == "transparent" {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: size * 0.72, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor
                            : Color.primary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
    }
}

private extension View {
    @ViewBuilder
    func applyIconColorScheme(_ colorScheme: ColorScheme) -> some View {
        if colorScheme == .dark {
            colorInvert()
        } else {
            self
        }
    }
}

private struct ElementPropertyLinePreview: View {
    let style: ExcalidrawStrokeStyle

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 3, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))
            context.stroke(
                path,
                with: .color(.primary),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: dash
                )
            )
        }
        .frame(width: 24, height: 16)
    }

    private var dash: [CGFloat] {
        switch style {
            case .solid:
                []
            case .dashed:
                [6, 4]
            case .dotted:
                [1, 4]
        }
    }
}
