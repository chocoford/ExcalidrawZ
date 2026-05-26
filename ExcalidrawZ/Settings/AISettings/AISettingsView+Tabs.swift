//
//  AISettingsView+Tabs.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI

extension AISettingsView {
    @MainActor @ViewBuilder
    func settingsTabHeader<Leading: View, Accessory: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 22) {
            leading()

            Spacer(minLength: 0)

            if prefs.isAIEnabled {
                VStack(alignment: .trailing, spacing: 12) {
                    tabPicker
                    accessory()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor @ViewBuilder
    func settingsTabHeader<Leading: View>(
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        settingsTabHeader(leading: leading) {
            EmptyView()
        }
    }

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
        if !prefs.isAIEnabled {
            informationSection
        } else {
            selectedEnabledTabContent
        }
    }

    @MainActor @ViewBuilder
    var selectedEnabledTabContent: some View {
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
            case .information:
                informationSection
        }
    }

    @MainActor @ViewBuilder
    var informationSection: some View {
        Section {
            aiInformationRows
        } header: {
            informationHeader
                .textCase(nil)
        }
    }
}
