//
//  SettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if !APP_STORE
import Sparkle
#endif

struct SettingsView: View {
    @State private var selection: Route? = .general

    var body: some View {
        content()
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
                    .toolbar(removing: .sidebarToggle)
                    .background(
                        List(selection: $selection) {}
                    )
            } detail: {
                detail(for: selection)
            }
            .navigationTitle("App Settings")
        } else if #available(macOS 13.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
                    .background(
                        List(selection: $selection) {}
                    )
            } detail: {
                detail(for: selection)
            }
            .removeSettingsSidebarToggle()
            .navigationTitle("App Settings")
        } else {
            HStack {
                sidebar
                    .visualEffect(material: .sidebar)
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
                    .buttonStyle(ListButtonStyle(showIndicator: true,
                                                 selected: selection == route))
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func detail(for selection: Route?) -> some View {
        if let route = selection {
#if os(macOS)
            ScrollView {
                detailView(for: route)
            }
#elseif os(iOS)
            detailView(for: route)
#endif
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
        }
    }
}

extension SettingsView {
    enum Route: CaseIterable, Identifiable {
        case general
        
        var text: String {
            switch self {
                case .general:
                    return "General"
            }
        }
        
        var id: String {
            self.text
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
