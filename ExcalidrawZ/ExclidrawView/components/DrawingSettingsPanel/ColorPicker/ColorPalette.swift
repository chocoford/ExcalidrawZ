//
//  ColorPalette.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import Foundation

/// Color palette definitions from excalidraw's open-color library
struct ColorPalette {
    // MARK: - Quick Pick Colors

    /// Stroke colors: black, red[8], green[8], blue[8], yellow[8]
    /// These are the default colors shown in the quick pick bar for stroke
    static let strokeQuickPicks: [String] = [
        "#1e1e1e",  // black
        "#e03131",  // red[8]
        "#2f9e44",  // green[8]
        "#1971c2",  // blue[8]
        "#f08c00"   // yellow[8]
    ]

    /// Background colors: transparent, red[2], green[2], blue[2], yellow[2]
    /// These are the default colors shown in the quick pick bar for background
    static let backgroundQuickPicks: [String] = [
        "transparent",  // transparent
        "#ffc9c9",      // red[2]
        "#b2f2bb",      // green[2]
        "#a5d8ff",      // blue[2]
        "#ffec99"       // yellow[2]
    ]

    // MARK: - Transparent Pattern

    /// Base64 encoded 16x16 PNG checkboard pattern from excalidraw
    /// This is used to visually represent transparency
    static let transparentPatternBase64 = "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAMUlEQVQ4T2NkYGAQYcAP3uCTZhw1gGGYhAGBZIA/nYDCgBDAm9BGDWAAJyRCgLaBCAAgXwixzAS0pgAAAABJRU5ErkJggg=="

    // MARK: - Full Color Palette

    /// Open-color palette with 5 shades per color (indexes 0, 2, 4, 6, 8)
    /// Each color family contains shades from lightest to darkest
    static let fullPalette: [(name: String, shades: [String])] = [
        ("transparent", ["transparent"]),
        ("black", ["#1e1e1e"]),
        ("white", ["#ffffff"]),
        ("gray", ["#f8f9fa", "#e9ecef", "#ced4da", "#868e96", "#343a40"]),
        ("bronze", ["#f8f1ee", "#eaddd7", "#d2bab0", "#a18072", "#846358"]),
        ("red", ["#fff5f5", "#ffc9c9", "#ff8787", "#fa5252", "#e03131"]),
        ("pink", ["#fff0f6", "#fcc2d7", "#f783ac", "#e64980", "#c2255c"]),
        ("grape", ["#f8f0fc", "#eebefa", "#da77f2", "#be4bdb", "#9c36b5"]),
        ("violet", ["#f3f0ff", "#d0bfff", "#9775fa", "#7950f2", "#6741d9"]),
        ("blue", ["#e7f5ff", "#a5d8ff", "#4dabf7", "#228be6", "#1971c2"]),
        ("cyan", ["#e3fafc", "#99e9f2", "#3bc9db", "#15aabf", "#0c8599"]),
        ("teal", ["#e6fcf5", "#96f2d7", "#38d9a9", "#12b886", "#099268"]),
        ("green", ["#ebfbee", "#b2f2bb", "#69db7c", "#40c057", "#2f9e44"]),
        ("yellow", ["#fff9db", "#ffec99", "#ffd43b", "#fab005", "#f08c00"]),
        ("orange", ["#fff4e6", "#ffd8a8", "#ffa94d", "#fd7e14", "#e8590c"])
    ]

    /// Get base color (middle shade or single color) for each color family
    static func getBaseColor(for colorFamily: (name: String, shades: [String])) -> String {
        let shades = colorFamily.shades
        if shades.count == 1 {
            return shades[0]
        }
        // Return middle shade (index 2 for 5-shade colors)
        return shades[min(2, shades.count - 1)]
    }

    /// Get all shades for a specific color
    static func getShades(for color: String) -> [String]? {
        return fullPalette.first { family in
            family.shades.contains(color)
        }?.shades
    }
}
