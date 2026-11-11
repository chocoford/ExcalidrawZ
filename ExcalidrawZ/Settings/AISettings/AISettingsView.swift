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
    @ObservedObject var inferenceBilling = AIInferenceBillingState.shared
    @ObservedObject var aiServiceConsent = AIServiceConsentState.shared
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
    @State var isPresentingMCPBasicReadMeEditor: Bool = false
    @State var mcpBasicReadMeDraft: String = ""
    @State var selectedMCPConnectionGuideTab: MCPConnectionGuideTab = .claude
    @State var mcpServiceModePickerID = UUID()
    @State var pendingAIServiceMode: AIServiceMode?
    @State var preferredSettingsSection: SettingsSection = .general
    @State var byokStatusMessage: String?
    @State var byokStatusIsError = false
    @State var byokConnectionSheet: AIInferenceConnectionSheet?
    @State var byokIntegrationHelpMode: AIInferenceIntegrationMode?
    @State var byokIntegrationPickerID = UUID()

    @ObservedObject var schemeCatalog = AIChatSchemeCatalog.shared
    @ObservedObject var routing = AIChatRoutingState.shared

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
        .sheet(item: $pendingAIServiceMode) { mode in
            AIEnableConsentSheet(mode: mode.billingMode ?? .platform) {
                guard let billingMode = mode.billingMode else { return }
                aiServiceConsent.accept(billingMode)
                applyAIServiceMode(mode)
            }
        }
        .sheet(isPresented: $isPresentingMCPConnectionGuide) {
            mcpConnectionGuideSheet
        }
        .sheet(isPresented: $isPresentingMCPServiceModeHelp) {
            mcpServiceModeHelpSheet
        }
        .sheet(isPresented: $isPresentingMCPBasicReadMeEditor) {
            mcpBasicReadMeEditorSheet
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
        .watch(value: inferenceBilling.mode) {
            Task { await loadAISettingsDataIfEnabled() }
        }
        .watch(value: inferenceBilling.integrationMode) {
            Task { await loadAISettingsDataIfEnabled() }
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
        guard AIChatAvailability.canUseAI, !AIChatAvailability.usesDirectInference else { return }
        await LLMServiceActivationCoordinator.shared.restoreIfAIEnabled(reason: .aiSettingsAppear)
        await loadInitialTransactions()
        await loadAllTransactionsIfNeeded()
        await loadAvailableModelsIfNeeded()
        await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiSettingsAppear)
        await loadAIAccountInfoIfNeeded()
    }
    
}
