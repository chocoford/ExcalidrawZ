//
//  AppPreference.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import os.log

import ChocofordUI
import UniformTypeIdentifiers

final class AppPreference: ObservableObject {
    enum SidebarMode: Sendable {
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
    @Published var sidebarMode: SidebarMode = .all
//    @AppStorage("sidebarLayout")
    @Published
    var sidebarLayout: LayoutStyle = {
        if #available(macOS 13.0, *) {
            return .sidebar
        } else {
            return .floatingBar
        }
    }()
    
//    @AppStorage("inspectorLayout")
    @Published
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
                    return "light"
                case .dark:
                    return "dark"
                case .auto:
                    return "auto"
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
    @AppStorage("appearance") var appearance: Appearance = .auto
    @AppStorage("excalidrawAppearance") var excalidrawAppearance: Appearance = .auto
    
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
}
