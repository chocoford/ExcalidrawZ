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
    @EnvironmentObject var llmState: LLMStateObject
    @EnvironmentObject var store: Store
    @ObservedObject var prefs = AIChatPreferences.shared
    @ObservedObject var router = SettingsRouter.shared

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

    /// Model list for the Default Model picker, sourced from the agent's
    /// `allowedModels`. Loaded lazily on first appearance so opening
    /// Settings doesn't pay a network cost up-front.
    @State var availableModels: [SupportedModel] = []

    let pageSize: Int = 20
    let aggregatePageSize: Int = 100
    let agentID = "excalidraw-canvas"

    var body: some View {
        SwiftUI.Group {
            if #available(macOS 14.0, iOS 17.0, *) {
                Form {
                    selectedTabContent
                }
                .formStyle(.grouped)
                .task { await loadInitialTransactions() }
                .task { await loadAllTransactionsIfNeeded() }
                .task { await loadAvailableModelsIfNeeded() }
                .task { await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiSettingsAppear) }
                .task { await loadAIAccountInfoIfNeeded() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        selectedTabContent
                    }
                    .padding()
                }
                .task { await loadInitialTransactions() }
                .task { await loadAllTransactionsIfNeeded() }
                .task { await loadAvailableModelsIfNeeded() }
                .task { await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiSettingsAppear) }
                .task { await loadAIAccountInfoIfNeeded() }
            }
        }
        .task {
            consumePendingAISettingsRoute()
        }
        .watch(value: router.pendingAISettingsRoute) {
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
                selectedTab = .settings
        }
        router.pendingAISettingsRoute = nil
    }
}
