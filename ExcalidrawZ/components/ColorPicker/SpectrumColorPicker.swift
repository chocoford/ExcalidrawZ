//
//  SpectrumColorPicker.swift
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

/// A self-contained color picker that never presents the platform color panel.
///
/// The component is domain-independent: callers provide a SwiftUI `Color`
/// binding and decide whether it belongs in a popover, sheet, or inline panel.
struct SpectrumColorPicker: View {
    @Binding private var selection: Color

    private let showsOpacity: Bool
    private let onConfirm: (() -> Void)?

    @State private var color: HSBAColor
    @State private var hexInput: String
#if os(macOS)
    @State private var colorSampler: NSColorSampler?
#endif

    init(
        selection: Binding<Color>,
        showsOpacity: Bool = false,
        onConfirm: (() -> Void)? = nil
    ) {
        let color = HSBAColor(selection.wrappedValue)
        _selection = selection
        self.showsOpacity = showsOpacity
        self.onConfirm = onConfirm
        _color = State(initialValue: color)
        _hexInput = State(initialValue: color.hexString(includesAlpha: showsOpacity))
    }

    var body: some View {
        VStack(spacing: 12) {
            saturationBrightnessField
                .frame(height: 156)

            hueSlider
                .frame(height: 16)

            if showsOpacity {
                opacitySlider
                    .frame(height: 16)
            }

            colorValueRow
        }
        .frame(minWidth: 220, idealWidth: 260)
        .watch(value: HSBAColor(selection).hexString(includesAlpha: true)) {
            _, _ in
            let newValue = HSBAColor(selection)
            guard newValue.hexString(includesAlpha: true)
                    != color.hexString(includesAlpha: true)
            else {
                return
            }
            color = newValue
            hexInput = newValue.hexString(includesAlpha: showsOpacity)
        }
    }

    private var saturationBrightnessField: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(
                    hue: color.hue,
                    saturation: 1,
                    brightness: 1
                )
                .overlay {
                    LinearGradient(
                        colors: [.white, .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                selectionIndicator
                    .position(
                        x: 8 + color.saturation * max(proxy.size.width - 16, 0),
                        y: 8 + (1 - color.brightness)
                            * max(proxy.size.height - 16, 0)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary.opacity(0.16))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        color.saturation = normalized(
                            value.location.x,
                            upperBound: proxy.size.width
                        )
                        color.brightness = 1 - normalized(
                            value.location.y,
                            upperBound: proxy.size.height
                        )
                        commitColor()
                    }
            )
        }
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
                        .map {
                            Color(hue: $0, saturation: 1, brightness: 1)
                        },
                    startPoint: .leading,
                    endPoint: .trailing
                )

                sliderIndicator
                    .position(
                        x: color.hue * proxy.size.width,
                        y: proxy.size.height / 2
                    )
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(0.16))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        color.hue = normalized(
                            value.location.x,
                            upperBound: proxy.size.width
                        )
                        commitColor()
                    }
            )
        }
    }

    private var opacitySlider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ColorPickerCheckerboard()

                LinearGradient(
                    colors: [
                        color.opaqueSwiftUIColor.opacity(0),
                        color.opaqueSwiftUIColor,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                sliderIndicator
                    .position(
                        x: color.alpha * proxy.size.width,
                        y: proxy.size.height / 2
                    )
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(0.16))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        color.alpha = normalized(
                            value.location.x,
                            upperBound: proxy.size.width
                        )
                        commitColor()
                    }
            )
        }
    }

    private var colorValueRow: some View {
        HStack(spacing: 8) {
            ZStack {
                ColorPickerCheckerboard()
                color.swiftUIColor
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(0.16))
            }

            TextField(showsOpacity ? "#RRGGBBAA" : "#RRGGBB", text: $hexInput)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    confirmSelection()
                }

#if os(macOS)
            Button {
                sampleScreenColor()
            } label: {
                Image(systemName: "eyedropper")
            }
            .modernButtonStyle(style: .glass, size: .small, shape: .circle)
#endif

            Button {
                confirmSelection()
            } label: {
                Image(systemName: "checkmark")
            }
            .modernButtonStyle(style: .glass, size: .small, shape: .circle)
            .disabled(parsedHexInput == nil)
        }
    }

    private var selectionIndicator: some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.45), radius: 1.5)
    }

    private var sliderIndicator: some View {
        Capsule()
            .fill(.white)
            .frame(width: 5, height: 20)
            .overlay {
                Capsule()
                    .strokeBorder(.black.opacity(0.35))
            }
            .shadow(color: .black.opacity(0.25), radius: 1)
    }

    private var parsedHexInput: HSBAColor? {
        HSBAColor(hexString: hexInput, defaultAlpha: color.alpha)
    }

    private func normalized(_ value: CGFloat, upperBound: CGFloat) -> Double {
        guard upperBound > 0 else { return 0 }
        return min(max(Double(value / upperBound), 0), 1)
    }

    private func applyHexInput() {
        guard let parsedHexInput else { return }
        color = parsedHexInput
        commitColor()
    }

    private func confirmSelection() {
        guard parsedHexInput != nil else { return }
        applyHexInput()
        onConfirm?()
    }

    private func commitColor() {
        selection = color.swiftUIColor
        hexInput = color.hexString(includesAlpha: showsOpacity)
    }

#if os(macOS)
    private func sampleScreenColor() {
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { sampledColor in
            Task { @MainActor in
                colorSampler = nil
                guard let sampledColor else { return }
                color = HSBAColor(Color(nsColor: sampledColor))
                commitColor()
            }
        }
    }
#endif
}

private struct ColorPickerCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let cellLength: CGFloat = 5
            let columns = Int(ceil(size.width / cellLength))
            let rows = Int(ceil(size.height / cellLength))

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white)
            )
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cellLength,
                                y: CGFloat(row) * cellLength,
                                width: cellLength,
                                height: cellLength
                            )
                        ),
                        with: .color(Color(white: 0.78))
                    )
                }
            }
        }
    }
}

private struct HSBAColor: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var alpha: Double

    init(_ color: Color) {
#if os(macOS)
        let platformColor = NSColor(color).usingColorSpace(.deviceRGB)
            ?? NSColor.black
#else
        let platformColor = UIColor(color)
#endif
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        platformColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        self.init(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness),
            alpha: Double(alpha)
        )
    }

    init(
        hue: Double,
        saturation: Double,
        brightness: Double,
        alpha: Double
    ) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.alpha = alpha
    }

    init?(hexString: String, defaultAlpha: Double) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard [3, 6, 8].contains(value.count),
              value.allSatisfy({ $0.isHexDigit })
        else {
            return nil
        }

        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard let rgb = UInt64(value.prefix(6), radix: 16) else {
            return nil
        }
        let red = Double((rgb >> 16) & 0xff) / 255
        let green = Double((rgb >> 8) & 0xff) / 255
        let blue = Double(rgb & 0xff) / 255
        let alpha: Double
        if value.count == 8,
           let alphaValue = UInt64(value.suffix(2), radix: 16) {
            alpha = Double(alphaValue) / 255
        } else {
            alpha = defaultAlpha
        }

        self = Self(red: red, green: green, blue: blue, alpha: alpha)
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let hue: Double

        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }

        self.init(
            hue: hue < 0 ? hue + 1 : hue,
            saturation: maximum == 0 ? 0 : delta / maximum,
            brightness: maximum,
            alpha: alpha
        )
    }

    var swiftUIColor: Color {
        Color(
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            opacity: alpha
        )
    }

    var opaqueSwiftUIColor: Color {
        Color(
            hue: hue,
            saturation: saturation,
            brightness: brightness
        )
    }

    func hexString(includesAlpha: Bool) -> String {
        let rgb = rgbComponents
        let red = Int((rgb.red * 255).rounded())
        let green = Int((rgb.green * 255).rounded())
        let blue = Int((rgb.blue * 255).rounded())
        let alpha = Int((alpha * 255).rounded())
        return includesAlpha
            ? String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
            : String(format: "#%02X%02X%02X", red, green, blue)
    }

    private var rgbComponents: (red: Double, green: Double, blue: Double) {
        let sector = hue * 6
        let chroma = brightness * saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma
        let components: (Double, Double, Double)

        switch sector {
            case 0..<1:
                components = (chroma, secondary, 0)
            case 1..<2:
                components = (secondary, chroma, 0)
            case 2..<3:
                components = (0, chroma, secondary)
            case 3..<4:
                components = (0, secondary, chroma)
            case 4..<5:
                components = (secondary, 0, chroma)
            default:
                components = (chroma, 0, secondary)
        }
        return (
            components.0 + match,
            components.1 + match,
            components.2 + match
        )
    }
}
