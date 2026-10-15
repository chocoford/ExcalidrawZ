//
//  SharedAppAppearance.swift
//  ExcalidrawZ
//

import Foundation

enum SharedAppAppearance: String {
    case light
    case dark
    case auto

    /// Automatic canvas appearance inherits the app preference; automatic app
    /// appearance leaves the final choice to the system.
    static func resolve(canvas: Self, app: Self) -> Self {
        canvas == .auto ? app : canvas
    }
}

enum SharedAppAppearanceStore {
    static let appearanceKey = "appearance"
    static let canvasAppearanceKey = "excalidrawAppearance"

    private static let appGroupInfoKey = "ExcalidrawZAppGroupIdentifier"

    static let defaults: UserDefaults = {
        guard let appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: appGroupInfoKey
        ) as? String,
        !appGroupIdentifier.isEmpty,
        let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return .standard
        }
        return defaults
    }()

    static func save(
        _ appearance: SharedAppAppearance,
        canvasAppearance: SharedAppAppearance
    ) {
        defaults.set(appearance.rawValue, forKey: appearanceKey)
        defaults.set(canvasAppearance.rawValue, forKey: canvasAppearanceKey)
    }
}
