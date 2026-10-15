//
//  ViewerPointerAppearance.swift
//  ExcalidrawZ
//

#if os(macOS)
import Foundation

/// Display preferences for the presenter's pointer in Viewer only.
struct ViewerPointerAppearance: Codable, Equatable {
    static let defaultColorHex = ColorPalette.collaboratorQuickPicks[0]

    var isVisible = true
    /// Older preferences with no explicit color resolve to defaultColorHex on load.
    var colorHex: String? = Self.defaultColorHex

    private static let defaultsKey = "ViewerPointerAppearance"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              var appearance = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        appearance.colorHex = appearance.colorHex.flatMap(Self.normalizedColorHex) ?? Self.defaultColorHex
        return appearance
    }

    static func normalizedColorHex(_ value: String) -> String? {
        guard value.hasPrefix("#") else { return nil }
        let digits = value.dropFirst()
        guard (digits.count == 3 || digits.count == 6),
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let expanded = digits.count == 3
            ? digits.map { String(repeating: String($0), count: 2) }.joined()
            : String(digits)
        return "#" + expanded.lowercased()
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
#endif
