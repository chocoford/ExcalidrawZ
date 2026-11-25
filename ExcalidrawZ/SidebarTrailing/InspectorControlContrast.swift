import Foundation

enum InspectorControlContrast {
    static func prefersWhiteForeground(backgroundColor: String, isDark: Bool) -> Bool {
        let rgba = components(backgroundColor) ?? [1, 1, 1, 1]
        let rgb = isDark ? darkModeRGB(Array(rgba.prefix(3))) : Array(rgba.prefix(3))
        let backdrop = isDark ? 18.0 / 255 : 1
        let blended = rgb.map { $0 * rgba[3] + backdrop * (1 - rgba[3]) }
        let linear = blended.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return whiteContrast > blackContrast
    }

    private static func components(_ color: String) -> [Double]? {
        let color = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if color == "transparent" { return [0, 0, 0, 0] }
        guard color.hasPrefix("#") else { return nil }
        var hex = String(color.dropFirst())
        if hex.count == 3 || hex.count == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? (value << 8) | 0xff : value
        return [24, 16, 8, 0].map { Double((rgba >> $0) & 0xff) / 255 }
    }

    private static func darkModeRGB(_ rgb: [Double]) -> [Double] {
        // Match Excalidraw's invert(93%) hue-rotate(180deg), including the
        // byte rounding used by its applyDarkModeFilter color mapping.
        let inverted = rgb.map { ((0.93 - 0.86 * $0) * 255).rounded() / 255 }
        let r = inverted[0], g = inverted[1], b = inverted[2]
        return [
            -0.574 * r + 1.430 * g + 0.144 * b,
             0.426 * r + 0.430 * g + 0.144 * b,
             0.426 * r + 1.430 * g - 0.856 * b,
        ].map { (min(max($0, 0), 1) * 255).rounded() / 255 }
    }
}
