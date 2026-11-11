//
//  AISettingsView+Tabs.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI

extension AISettingsView {
    @ViewBuilder
    func settingsTabHeader<Leading: View, Accessory: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
#if os(macOS)
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
#else
        if usesCompactSettingsLayout {
            VStack(alignment: .leading, spacing: 12) {
                leading()

                if prefs.isAIEnabled {
                    accessory()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    leading()

                    Spacer(minLength: 0)

                    if prefs.isAIEnabled {
                        VStack(alignment: .trailing, spacing: 12) {
                            if !usesToolbarSettingsTabs {
                                tabPicker
                            }
                            accessory()
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 12) {
                    leading()

                    if prefs.isAIEnabled {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .center, spacing: 12) {
                                if !usesToolbarSettingsTabs {
                                    tabPicker
                                }
                                accessory()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                if !usesToolbarSettingsTabs {
                                    tabPicker
                                }
                                accessory()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
#endif
    }

    @ViewBuilder
    func settingsTabHeader<Leading: View>(
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        settingsTabHeader(leading: leading) {
            EmptyView()
        }
    }

#if os(iOS)
    @ViewBuilder
    var bottomTabBar: some View {
        ForEach(SettingsTab.allCases) { tab in
            toolbarTabButton(tab)
        }
    }

    @ViewBuilder
    var toolbarTabBar: some View {
        ForEach(SettingsTab.allCases) { tab in
            toolbarTabButton(tab)
        }
    }

    private func toolbarTabButton(_ tab: SettingsTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            Label(tab.title, systemSymbol: tab.iconSymbol)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
        .tint(selectedTab == tab ? Color.accentColor : Color.primary)
        .help(tab.title)
    }
#endif

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
        .fixedSize(horizontal: true, vertical: false)
        .padding(3)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        }
    }

    @ViewBuilder
    var selectedTabContent: some View {
        if !prefs.isAIEnabled {
            if selectedTab == .settings,
               preferredSettingsSection == .mcp {
                mcpSettingsSection
            } else {
                informationSection
            }
        } else {
            selectedEnabledTabContent
        }
    }

    @ViewBuilder
    var selectedEnabledTabContent: some View {
        switch selectedTab {
            case .usage:
                Section {
                    if AIChatAvailability.usesDirectInference {
                        Text(.localizable(.aIDirectNoCredits))
                    } else {
                        activityBody
                    }
                } header: {
                    VStack(spacing: 10) {
                        usageHeader
                            .textCase(nil)

                        if !AIChatAvailability.usesDirectInference {
                            activityHeader
                        }
                    }
                }
            case .settings:
                settingsSections
            case .information:
                informationSection
        }
    }

    @ViewBuilder
    var settingsSections: some View {
        defaultModelSettingsSection
        mcpSettingsSection
        aiAccountSettingsSection
    }

    @ViewBuilder
    var defaultModelSettingsSection: some View {
        Section {
            aiServiceModePicker
            if inferenceBilling.usesBYOK {
                byokIntegrationModeRow
                byokConnectionsRow
                basicWebSearchRow
            } else {
                defaultModelPicker
            }
        } header: {
            settingsHeader
                .textCase(nil)
        } footer: {
            aiServiceSettingsFooter
            if inferenceBilling.usesBYOK {
                byokConnectionsFooter
            } else {
                platformModelStatusFooter
            }
        }
    }

    @ViewBuilder
    var aiAccountSettingsSection: some View {
        Section {
            aiAccountRows
        } header: {
            aiAccountHeader
                .textCase(nil)
        }
    }

    @ViewBuilder
    var informationSection: some View {
        Section {
            aiInformationRows
        } header: {
            informationHeader
                .textCase(nil)
        } footer: {
            if !prefs.isAIEnabled {
                Text(localizable: .settingsAIEnableFeatureHelp)
                aiServiceSettingsFooter
            }
        }
    }
}
