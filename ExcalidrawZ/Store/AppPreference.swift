//
//  AppPreference.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Observation
import SwiftUI
import WebKit
import Combine
import Logging

import ChocofordUI
import UniformTypeIdentifiers

private let appPreferenceLogger = Logger(label: "AppPreference")

@Observable
final class AppPreference {
    enum SidebarMode: Hashable, Sendable {
        case all
        case filesOnly
    }
    enum LayoutStyle: Int, Sendable, RadioGroupCase, Hashable {
        case sidebar
        case floatingBar
        
        var id: Int { rawValue }
        
        func imageName(_ name: String) -> String {
            switch self {
                case .sidebar:
                    "Layout-\(name)-Modern"
                case .floatingBar:
                    "Layout-\(name)-Floating"
            }
        }
        
        var availability: Bool {
            switch self {
                case .sidebar:
                    if #available(macOS 13.0, *) {
                        return true
                    } else {
                        return false
                    }
                case .floatingBar:
                    return true
            }
        }
    }
    // Layout
    var sidebarMode: SidebarMode = .all
    var sidebarLayout: LayoutStyle = {
        if #available(macOS 13.0, *) {
            return .sidebar
        } else {
            return .floatingBar
        }
    }()
    
    var inspectorLayout: LayoutStyle = {
        if #available(macOS 14.0, *) {
            return .sidebar
        } else {
            return .floatingBar
        }
    }()
    // Appearence
    enum Appearance: String, RadioGroupCase {
        case light
        case dark
        case auto
        
        var text: String {
            switch self {
                case .light:
                    return String(localizable: .settingsAppearanceColorScemeLight)
                case .dark:
                    return String(localizable: .settingsAppearanceColorScemeDark)
                case .auto:
                    return String(localizable: .settingsAppearanceColorScemeAuto)
            }
        }
        
        var id: String {
            self.text
        }
        
        var colorScheme: ColorScheme? {
            switch self {
                case .light:
                    return .light
                case .dark:
                    return .dark
                case .auto:
                    return nil
            }
        }
    }
    @ObservationIgnored @AppStorage("appearance") private var persistedStoredAppearance: Appearance = .auto
    private var storedAppearance: Appearance {
        get {
            access(keyPath: \.storedAppearance)
            return persistedStoredAppearance
        }
        set {
            guard persistedStoredAppearance != newValue else { return }
            withMutation(keyPath: \.storedAppearance) {
                persistedStoredAppearance = newValue
            }
        }
    }
    @ObservationIgnored @AppStorage("excalidrawAppearance") private var persistedStoredExcalidrawAppearance: Appearance = .auto
    private var storedExcalidrawAppearance: Appearance {
        get {
            access(keyPath: \.storedExcalidrawAppearance)
            return persistedStoredExcalidrawAppearance
        }
        set {
            guard persistedStoredExcalidrawAppearance != newValue else { return }
            withMutation(keyPath: \.storedExcalidrawAppearance) {
                persistedStoredExcalidrawAppearance = newValue
            }
        }
    }

    var appearance: Appearance {
        get { storedAppearance }
        set {
            guard storedAppearance != newValue else { return }
            storedAppearance = newValue
            synchronizeSharedAppearance()
        }
    }

    var excalidrawAppearance: Appearance {
        get { storedExcalidrawAppearance }
        set {
            guard storedExcalidrawAppearance != newValue else { return }
            storedExcalidrawAppearance = newValue
            synchronizeSharedAppearance()
        }
    }

    init() {
        synchronizeSharedAppearance()
    }

    private func synchronizeSharedAppearance() {
        SharedAppAppearanceStore.save(
            SharedAppAppearance(rawValue: storedAppearance.rawValue) ?? .auto,
            canvasAppearance: SharedAppAppearance(rawValue: storedExcalidrawAppearance.rawValue) ?? .auto
        )
    }
    
    var appearanceBinding: Binding<ColorScheme?> {
        Binding {
            self.appearance.colorScheme
        } set: { val in
            switch val {
                case .light:
                    self.appearance = .light
                case .dark:
                    self.appearance = .dark
                case .none:
                    self.appearance = .auto
                case .some(_):
                    self.appearance = .light
            }
        }
    }
    /// Invert the inverted image in dark mode.
    @ObservationIgnored @AppStorage("autoInvertImage") private var persistedAutoInvertImage: Bool = true
    var autoInvertImage: Bool {
        get {
            access(keyPath: \.autoInvertImage)
            return persistedAutoInvertImage
        }
        set {
            guard persistedAutoInvertImage != newValue else { return }
            withMutation(keyPath: \.autoInvertImage) {
                persistedAutoInvertImage = newValue
            }
        }
    }
    @ObservationIgnored @AppStorage("autoInvertImageSettings") private var persistedAutoInvertImageSettings: String = ""
    private var autoInvertImageSettings: String {
        get {
            access(keyPath: \.autoInvertImageSettings)
            return persistedAutoInvertImageSettings
        }
        set {
            guard persistedAutoInvertImageSettings != newValue else { return }
            withMutation(keyPath: \.autoInvertImageSettings) {
                persistedAutoInvertImageSettings = newValue
            }
        }
    }
    
    var antiInvertImageSettings: AntiInvertImageSettings {
        get {
            do {
                guard let data = autoInvertImageSettings.data(using: .utf8) else {
                    return AntiInvertImageSettings()
                }
                return try JSONDecoder().decode(AntiInvertImageSettings.self, from: data)
            } catch {
                return AntiInvertImageSettings()
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                if let string = String(data: data, encoding: .utf8) {
                    self.autoInvertImageSettings = string
                }
            } catch {

            }
        }
    }

    // User Drawing Settings
    @ObservationIgnored @AppStorage("useCustomDrawingSettings") private var persistedUseCustomDrawingSettings: Bool = false
    var useCustomDrawingSettings: Bool {
        get {
            access(keyPath: \.useCustomDrawingSettings)
            return persistedUseCustomDrawingSettings
        }
        set {
            guard persistedUseCustomDrawingSettings != newValue else { return }
            withMutation(keyPath: \.useCustomDrawingSettings) {
                persistedUseCustomDrawingSettings = newValue
            }
        }
    }
    @ObservationIgnored @AppStorage("customDrawingSettingsData") private var persistedCustomDrawingSettingsData: Data = Data()
    private var customDrawingSettingsData: Data {
        get {
            access(keyPath: \.customDrawingSettingsData)
            return persistedCustomDrawingSettingsData
        }
        set {
            guard persistedCustomDrawingSettingsData != newValue else { return }
            withMutation(keyPath: \.customDrawingSettingsData) {
                persistedCustomDrawingSettingsData = newValue
            }
        }
    }
    @ObservationIgnored @AppStorage(ExcalidrawToolbarToolOrder.storageKey) private var persistedToolbarToolOrderData: Data = Data()
    private var toolbarToolOrderData: Data {
        get {
            access(keyPath: \.toolbarToolOrderData)
            return persistedToolbarToolOrderData
        }
        set {
            guard persistedToolbarToolOrderData != newValue else { return }
            withMutation(keyPath: \.toolbarToolOrderData) {
                persistedToolbarToolOrderData = newValue
            }
        }
    }
    @ObservationIgnored private var cachedToolbarToolOrderData: Data?
    @ObservationIgnored private var cachedToolbarToolOrder: ExcalidrawToolbarToolOrder?

    var customDrawingSettings: UserDrawingSettings {
        get {
            guard !customDrawingSettingsData.isEmpty else {
                return UserDrawingSettings()
            }

            do {
                let settings = try JSONDecoder().decode(UserDrawingSettings.self, from: customDrawingSettingsData)
                return settings
            } catch {
                appPreferenceLogger.warning("Failed to decode custom drawing settings: \(error)")
                return UserDrawingSettings()
            }
            
        }
        set {
            customDrawingSettingsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var toolbarToolOrder: ExcalidrawToolbarToolOrder {
        get {
            if let cachedToolbarToolOrderData,
               cachedToolbarToolOrderData == toolbarToolOrderData,
               let cachedToolbarToolOrder {
                return cachedToolbarToolOrder
            }

            let toolbarToolOrder = ExcalidrawToolbarToolOrder(storedData: toolbarToolOrderData)
            cachedToolbarToolOrderData = toolbarToolOrderData
            cachedToolbarToolOrder = toolbarToolOrder
            return toolbarToolOrder
        }
        set {
            let storedData = newValue.storedData
            cachedToolbarToolOrderData = storedData
            cachedToolbarToolOrder = newValue
            toolbarToolOrderData = storedData
        }
    }
}


struct AntiInvertImageSettings: Codable, Hashable {
    var png: Bool = true
    var svg: Bool = false
}
