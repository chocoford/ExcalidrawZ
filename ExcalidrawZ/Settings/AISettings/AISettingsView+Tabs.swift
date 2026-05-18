//
//  AISettingsView+Tabs.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI

extension AISettingsView {
    @ViewBuilder
    var tabPicker: some View {
        SwiftUI.Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    tabButtons
                }
            } else {
                tabButtons
            }
        }
    }

    @ViewBuilder
    var tabButtons: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(width: 72, height: 26)
                    .foregroundStyle(
                        selectedTab == tab ? Color.primary : Color.secondary
                    )
                    .background {
                        Capsule()
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        }
    }

    @MainActor @ViewBuilder
    var selectedTabContent: some View {
        switch selectedTab {
            case .usage:
                Section {
                    activityBody
                } header: {
                    VStack(spacing: 10) {
                        usageHeader
                            .textCase(nil)

                        activityHeader
                    }
                }
            case .settings:
                Section {
                    defaultModelPicker
                } header: {
                    settingsHeader
                        .textCase(nil)
                }

                Section {
                    aiAccountRows
                } header: {
                    aiAccountHeader
                        .textCase(nil)
                }
        }
    }
}
