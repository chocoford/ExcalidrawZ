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
#elseif os(iOS)
        List(selection: $selection) {
            Section {
                ForEach(Route.allCases) { route in
                    NavigationLink(value: route) {
                        Text(route.text)
                    }
                }
            } footer: {
                if containerVerticalSizeClass == .compact {
                    HStack {
                        Spacer()
                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Text(.localizable(.generalButtonClose))
                        }
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
                
//            case .fileHistory:
//                FileHistorySettingsView()
                
            case .medias:
                MediasSettingsView()
                
            case .backups:
                BackupsSettingsView()
                
#if os(iOS)
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
//        case fileHistory
        case medias
        case backups
#if os(iOS)
        case pencil
        case whatsNews
#endif
        
        case about
        
        var text: LocalizedStringKey {
            switch self {
                case .general:
                    return .localizable(.settingsGeneralName)
                    
//                case .fileHistory:
//                    return "File history"
                case .medias:
                    return .localizable(.settingsMediasName)
                    
                case .backups:
                    return .localizable(.settingsBackupsName)
#if os(iOS)
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
                case .general:
                    "general"
//                case .fileHistory:
//                    "fileHistory"
                case .medias:
                    "medias"
                case .backups:
                    "backups"
#if os(iOS)
                case .pencil:
                    "pencil"
                case .whatsNews:
                    "whatsNews"
#endif
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
