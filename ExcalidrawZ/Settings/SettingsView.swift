//
//  SettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols
#if os(macOS) && !APP_STORE
import Sparkle
#endif

struct SettingsView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    /// App-level deep-link bus — see `SettingsRouter` for the rationale on
    /// why this isn't `LayoutState`.
    @ObservedObject private var router = SettingsRouter.shared

    @State private var selection: Route?

    var body: some View {
        content()
            .task {
                // Honor a pending deep-link first; fall back to default tab.
                if let route = router.pendingRoute {
                    selection = route
                    router.pendingRoute = nil
                } else if selection == nil, containerHorizontalSizeClass != .compact {
                    selection = .general
                }
            }
            // The Settings window is reused across openings on macOS, so a
            // second deep-link request after the window already exists won't
            // re-fire `.task` — observe the published value to handle that.
            .watch(value: router.pendingRoute) { newValue in
                guard let newValue else { return }
                selection = newValue
                router.pendingRoute = nil
            }
    }

#if os(iOS)
    private var showsCompactIOSCreditsButton: Bool {
        containerHorizontalSizeClass == .compact &&
        aiChatPreferences.isAIEnabled &&
        AIChatAvailability.isAvailable
    }

    private func presentPaywallFromCompactIOSSettings() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            Store.shared.togglePaywall(reason: .manaully)
        }
    }
#endif
    
    @ViewBuilder
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
                        Label(route.text, systemSymbol: route.iconSymbol)
                            .labelStyle(.titleAndIcon)
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
                        Label(route.text, systemSymbol: route.iconSymbol)
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

            if showsCompactIOSCreditsButton {
                ToolbarItem(placement: .topBarTrailing) {
                    AICreditsToolbarButton {
                        presentPaywallFromCompactIOSSettings()
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
            case .security:
                SecuritySettingsView()
            case .cloudStorage:
                CloudStorageSettingsView()
            case .ai:
                AISettingsView()
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
    enum Route: CaseIterable, Identifiable, Hashable {
        case general
        case excalidraw
//        case fileHistory
        case medias
        case backups
        case security
        case cloudStorage
        case ai
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
                case .security:
                    return .localizable(.settingsSecurityName)
                case .cloudStorage:
                    return .localizable(.cloudStorageConnectedAccounts)
                case .ai:
                    // TODO: localize once a key is added.
                    return "AI"
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

        var iconSymbol: SFSymbol {
            switch self {
                case .general:
                    return .gearshape
                case .excalidraw:
                    return .pencilAndOutline
//                case .fileHistory:
//                    return .clockArrowCirclepath
                case .medias:
                    return .photoOnRectangle
                case .backups:
                    return .clockArrowCirclepath
                case .security:
                    return .lockShield
                case .cloudStorage:
                    return .externaldriveConnectedToLineBelow
                case .ai:
                    return .sparkles
#if os(macOS)
                case .fonts:
                    return .textformat
#elseif os(iOS)
                case .pencil:
                    return .pencilTip
                case .whatsNews:
                    return .sparkles
#endif
                case .about:
                    return .infoCircle
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
                case .security: "security"
                case .cloudStorage: "cloudStorage"
                case .ai: "ai"
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
