//
//  AISettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore

struct AISettingsView: View {
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var llmState: LLMStateObject
    @EnvironmentObject var store: Store
    @ObservedObject var prefs = AIChatPreferences.shared
    @ObservedObject var router = SettingsRouter.shared
    @ObservedObject var mcpServerController = ExcalidrawZMCPServerController.shared
    
    @State var selectedTab: SettingsTab = .usage
    @State var activityGrouping: ActivityGrouping = .recent
    @State var transactions: [CreditsTransaction] = []
    @State var totalTransactionCount: Int = 0
    @State var loadedPage: Int = 0
    @State var isLoadingTransactions: Bool = false
    @State var transactionLoadError: Error?
    @State var allTransactions: [CreditsTransaction] = []
    @State var allTransactionCount: Int = 0
    @State var isLoadingAllTransactions: Bool = false
    @State var allTransactionLoadError: Error?
    @State var aiUserInfo: AuthUserInfo?
    @State var isLoadingAIUserInfo: Bool = false
    @State var aiUserInfoLoadError: String?
    @State var didCopyAIAccountID: Bool = false
    @State var isPresentingMCPConnectionGuide: Bool = false
    @State var isPresentingMCPServiceModeHelp: Bool = false
    @State var selectedMCPConnectionGuideTab: MCPConnectionGuideTab = .claude
    @State var mcpServiceModePickerID = UUID()
    @State var isPresentingAIEnableConsent: Bool = false
    @State var preferredSettingsSection: SettingsSection = .general
    
    /// Model profile list for the Default Model picker, sourced from the
    /// agent's server-defined `modelProfiles`.
    @State var availableModelOptions: [ExcalidrawModelProfileOption] = []
    
    let pageSize: Int = 20
    let aggregatePageSize: Int = 100
    let agentID = "excalidraw-canvas"
    
    var usesCompactSettingsLayout: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    var usesToolbarSettingsTabs: Bool {
#if os(iOS)
        !usesCompactSettingsLayout
#else
        false
#endif
    }

    var canRunMCPServer: Bool {
        ExcalidrawZMCPServerController.isAvailable
    }

    @MainActor
    func presentPaywall(reason: Store.ReachPaywallReason) {
#if os(iOS)
        if usesCompactSettingsLayout {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                store.togglePaywall(reason: reason)
            }
            return
        }
#endif
        store.togglePaywall(reason: reason)
    }
    
    var body: some View {
        SwiftUI.Group {
            if #available(macOS 14.0, iOS 17.0, *) {
                Form {
                    selectedTabContent
                }
                .formStyle(.grouped)
                .task { await loadAISettingsDataIfEnabled() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        selectedTabContent
                    }
                    .padding()
                }
                .task { await loadAISettingsDataIfEnabled() }
            }
        }
#if os(iOS)
        .toolbar {
            if prefs.isAIEnabled {
                if usesCompactSettingsLayout {
                    ToolbarItemGroup(placement: .bottomBar) {
                        bottomTabBar
                    }
                } else {
                    ToolbarItemGroup(placement: .automatic) {
                        toolbarTabBar
                    }
                }
            }
        }
#endif
        .sheet(isPresented: $isPresentingAIEnableConsent) {
            AIEnableConsentSheet {
                prefs.isAIEnabled = true
            }
        }
        .sheet(isPresented: $isPresentingMCPConnectionGuide) {
            mcpConnectionGuideSheet
        }
        .sheet(isPresented: $isPresentingMCPServiceModeHelp) {
            mcpServiceModeHelpSheet
        }
        .watch(value: router.pendingAISettingsRoute) {
            consumePendingAISettingsRoute()
        }
        .watch(value: prefs.isAIEnabled) { _, isEnabled in
            guard isEnabled else { return }
            Task {
                await loadAISettingsDataIfEnabled()
            }
        }
        .task {
            consumePendingAISettingsRoute()
        }
    }
    
    @MainActor
    private func consumePendingAISettingsRoute() {
        guard let route = router.pendingAISettingsRoute else { return }
        switch route {
            case .usage:
                selectedTab = .usage
            case .settings:
                preferredSettingsSection = .general
                selectedTab = .settings
            case .mcp:
                preferredSettingsSection = .mcp
                selectedTab = .settings
        }
        router.pendingAISettingsRoute = nil
    }
    
    @MainActor
    private func loadAISettingsDataIfEnabled() async {
        guard AIChatAvailability.canUseAI else { return }
        await LLMServiceActivationCoordinator.shared.restoreIfAIEnabled(reason: .aiSettingsAppear)
        await loadInitialTransactions()
        await loadAllTransactionsIfNeeded()
        await loadAvailableModelsIfNeeded()
        await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiSettingsAppear)
        await loadAIAccountInfoIfNeeded()
    }
    
    @MainActor
    var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.isAIEnabled },
            set: { isEnabled in
                if isEnabled {
                    if !prefs.isAIEnabled {
                        isPresentingAIEnableConsent = true
                    }
                } else {
                    prefs.isAIEnabled = false
                }
            }
        )
    }
}
