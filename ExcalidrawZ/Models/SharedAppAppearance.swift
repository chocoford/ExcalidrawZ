//
//  SharedAppAppearance.swift
//  ExcalidrawZ
//

import Foundation

enum SharedAppAppearance: String {
    case light
    case dark
    case auto
}

enum SharedAppAppearanceStore {
    static let appearanceKey = "appearance"

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

    static func save(_ appearance: SharedAppAppearance) {
        defaults.set(appearance.rawValue, forKey: appearanceKey)
    }
}
