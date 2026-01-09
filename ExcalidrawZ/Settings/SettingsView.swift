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
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.dismiss) private var dismiss
    
    @State private var selection: Route?

    var body: some View {
        content()
            .task {
                if containerHorizontalSizeClass != .compact {
                    selection = .general
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            NavigationSplitView {
                sidebar
#if os(macOS)
                    .toolbar(removing: .sidebarToggle)
#endif
                    .navigationTitle(.localizable(.settingsNavigationTitle))
            } detail: {
                detail(for: selection)
            }
            
        } else if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
#if os(macOS)
                    .background(
                        List(selection: $selection) {}
                    )
#endif
                    .navigationTitle(.localizable(.settingsNavigationTitle))
            } detail: {
                detail(for: selection)
            }
#if os(macOS)
            .removeSettingsSidebarToggle()
#endif
        } else {
            HStack(spacing: 0) {
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
#if os(macOS)
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Route.allCases) { route in
                    Button {
                        selection = route
                    } label: {
                        Text(route.text)
                    }
                    .buttonStyle(
                        .excalidrawSidebarRow(
                            isSelected: selection == route,
                            isMultiSelected: false
                        )
                    )
                }
            }
            .padding(10)
        }
#elseif os(iOS)
        List(selection: $selection) {
            Section {
                ForEach(Route.allCases) { route in
                    NavigationLink(value: route) {
                        Text(route.text)
                    }
                }
            }
//            ForEach(Route.allCases) { route in
//                Button {
//                    selection = route
//                } label: {
//                    Text(route.text)
//                }
//                .buttonStyle(
//                    ListButtonStyle(
//                        showIndicator: true,
//                        selected: selection == route
//                    )
//                )
//            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if containerVerticalSizeClass == .compact {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                    }
                }
            }
        }
#endif
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
            case .excalidraw:
                ExcalidrawSettingsView()
//            case .fileHistory:
//                FileHistorySettingsView()
                
            case .medias:
                MediasSettingsView()
                
            case .backups:
                BackupsSettingsView()
#if os(macOS)
            case .fonts:
                FontsSettingsView()
#elseif os(iOS)
            case .pencil:
                PencilSettingsView()
                
            case .whatsNews:
                WhatsNewView(showContinue: false)
#endif
                
            case .about:
                AboutView()
        }
    }
}

extension SettingsView {
    enum Route: CaseIterable, Identifiable {
        case general
        case excalidraw
//        case fileHistory
        case medias
        case backups
#if os(macOS)
        case fonts
#elseif os(iOS)
        case pencil
        case whatsNews
#endif
        
        case about
        
        var text: LocalizedStringKey {
            switch self {
                case .general:
                    return .localizable(.settingsGeneralName)
                case .excalidraw:
                    return "Excalidraw"
//                case .fileHistory:
//                    return "File history"
                case .medias:
                    return .localizable(.settingsMediasName)
                    
                case .backups:
                    return .localizable(.settingsBackupsName)
#if os(macOS)
                case .fonts:
                    return .localizable(.settingsFontsName)
#elseif os(iOS)
                case .pencil:
                    return "Apple Pencil"
                case .whatsNews:
                    return .localizable(.whatsNewTitle)
#endif
                case .about:
                    return .localizable(.settingsAboutName)
            }
        }
        
        var id: String {
            switch self {
                case .general: "general"
                case .excalidraw: "excalidraw"
//                case .fileHistory:
//                    "fileHistory"
                case .medias: "medias"
                case .backups: "backups"
#if os(macOS)
                case .fonts: "fonts"
#elseif os(iOS)
                case .pencil: "pencil"
                case .whatsNews: "whatsNews"
#endif
                case .about: "about"
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
