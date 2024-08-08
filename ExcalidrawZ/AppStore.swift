//
//  AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/25.
//

import SwiftUI

import ChocofordUI

@Observable
final class AppPreference {
    enum SidebarMode: Sendable {
        case all
        case filesOnly
    }
    // Layout
    var sidebarMode: SidebarMode = .all
    
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
    @ObservationIgnored @AppStorage("appearance") var appearance: Appearance = .auto
    @ObservationIgnored @AppStorage("excalidrawAppearance") var excalidrawAppearance: Appearance = .auto
    
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


@Observable
final class DocumentModel {
    
}


final class FileState: ObservableObject {
    @Published var currentGroup: Group?
    @Published var currentFile: File?
    
}
