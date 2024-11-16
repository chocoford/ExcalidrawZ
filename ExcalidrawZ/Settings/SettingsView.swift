//
//  SettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if os(macOS) && !APP_STORE
import Sparkle
#endif

struct SettingsView: View {
    @State private var selection: Route? = .general

    var body: some View {
        content()
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                detail(for: selection)
            }
            .navigationTitle(.localizable(.settingsNavigationTitle))
        } else if #available(macOS 13.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
                    .background(
                        List(selection: $selection) {}
                    )
            } detail: {
                detail(for: selection)
            }
#if os(macOS)
            .removeSettingsSidebarToggle()
#endif
            .navigationTitle(.localizable(.settingsNavigationTitle))
        } else {
            HStack {
                sidebar
#if os(macOS)
                    .visualEffect(material: .sidebar)
#endif
                    .frame(width: 200)
                detail(for: selection)
            }
            .onAppear {
                if selection == nil {
                    selection = .general
                }
            }
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            VStack {
                ForEach(Route.allCases) { route in
                    Button {
                        selection = route
                    } label: {
                        Text(route.text)
                    }
                    .buttonStyle(
                        ListButtonStyle(
                            showIndicator: true,
                            selected: selection == route
                        )
                    )
                }
            }
            .padding(10)
        }
    }
    
    @ViewBuilder
    private func detail(for selection: Route?) -> some View {
        if let route = selection {
            detailView(for: route)
        } else {
            ZStack {
                Color.clear
                Text("No selection")
            }
        }
    }
    
    @ViewBuilder
    func detailView(for route: Route) -> some View {
        switch route {
            case .general:
                GeneralSettingsView()
                
//            case .fileHistory:
//                FileHistorySettingsView()
                
            case .medias:
                MediasSettingsView()
                
            case .backups:
                BackupsSettingsView()
                
            case .about:
                AboutView()
        }
    }
}

extension SettingsView {
    enum Route: CaseIterable, Identifiable {
        case general
//        case fileHistory
        case medias
        case backups
        
        case about
        
        var text: LocalizedStringKey {
            switch self {
                case .general:
                    return .localizable(.settingsGeneralName)
                    
//                case .fileHistory:
//                    return "File history"
                case .medias:
                    return "Media files"
                    
                case .backups:
                    return "Backups"
                    
                case .about:
                    return .localizable(.settingsAboutName)
            }
        }
        
        var id: String {
            switch self {
                case .general:
                    "general"
//                case .fileHistory:
//                    "fileHistory"
                case .medias:
                    "medias"
                case .backups:
                    "backups"
                case .about:
                    "about"
            }
        }
    }
}

#if DEBUG
//struct SettingsView_Previews: PreviewProvider {
//    static var previews: some View {
//        SettingsView()
//            .environmentObject(AppSettingsStore())
//            .environmentObject(UpdateChecker())
//    }
//}
#endif
