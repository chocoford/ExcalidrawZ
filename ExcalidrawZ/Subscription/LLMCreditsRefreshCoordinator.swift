//
//  LLMCreditsRefreshCoordinator.swift
//  ExcalidrawZ
//

import Foundation
import Logging
import LLMKit

actor LLMCreditsRefreshCoordinator {
    static let shared = LLMCreditsRefreshCoordinator()

    enum Reason: String, Sendable {
        case aiChatAppear
        case aiSettingsAppear
        case paywallAppear
        case storeKitEntitlementRefresh
    }

    private let logger = Logger(label: "LLMCreditsRefreshCoordinator")
    private let creditsRefreshThrottleInterval: TimeInterval = 30
    private let subscriptionSyncThrottleInterval: TimeInterval = 60
    private var lastCreditsRefreshAt: Date = .distantPast
    private var lastSubscriptionSyncAt: Date = .distantPast
    private var isRefreshingCredits = false
    private var isSyncingSubscription = false

    func refreshCredits(reason: Reason, force: Bool = false) async {
        let now = Date()
        if !force {
            let elapsed = now.timeIntervalSince(lastCreditsRefreshAt)
            guard elapsed >= creditsRefreshThrottleInterval else {
                logger.debug("[Credits] refresh skipped reason=\(reason.rawValue) throttleRemaining=\(String(format: "%.1f", creditsRefreshThrottleInterval - elapsed))s")
                return
            }
        }

        guard !isRefreshingCredits else {
            logger.debug("[Credits] refresh coalesced reason=\(reason.rawValue)")
            return
        }

        isRefreshingCredits = true
        lastCreditsRefreshAt = now
        defer { isRefreshingCredits = false }

        do {
            let info = try await LLMClient.shared.getCredits()
            logger.info("[Credits] refreshed reason=\(reason.rawValue) balance=\(info.balance)")
        } catch {
            logger.warning("[Credits] refresh failed reason=\(reason.rawValue) error=\(String(describing: error))")
        }
    }

#if APP_STORE
    func syncSubscriptionState(reason: Reason, force: Bool = false) async {
        let now = Date()
        if !force {
            let elapsed = now.timeIntervalSince(lastSubscriptionSyncAt)
            guard elapsed >= subscriptionSyncThrottleInterval else {
                logger.debug("[Credits] subscription sync skipped reason=\(reason.rawValue) throttleRemaining=\(String(format: "%.1f", subscriptionSyncThrottleInterval - elapsed))s")
                return
            }
        }

        guard !isSyncingSubscription else {
            logger.debug("[Credits] subscription sync coalesced reason=\(reason.rawValue)")
            return
        }

        isSyncingSubscription = true
        lastSubscriptionSyncAt = now
        defer { isSyncingSubscription = false }

        do {
            let state = try await LLMClient.shared.syncSubscriptionState()
            lastCreditsRefreshAt = Date()
            logger.info("[Credits] subscription synced reason=\(reason.rawValue) status=\(state.status.rawValue) productID=\(state.productId)")
        } catch {
            logger.warning("[Credits] subscription sync failed reason=\(reason.rawValue) error=\(String(describing: error))")
        }
    }

    func handleStoreKitEntitlementRefresh(
        reason: StoreKitEntitlementRefreshReason,
        force: Bool,
        entitlementChanged: Bool
    ) async {
        switch reason {
        case .restorePurchases:
            await syncSubscriptionState(reason: .storeKitEntitlementRefresh, force: true)
        case .purchase, .transactionUpdate, .entitlementExpirationTimer:
            await refreshCredits(reason: .storeKitEntitlementRefresh, force: true)
        case .paywallPresented:
            await refreshCredits(reason: .storeKitEntitlementRefresh, force: entitlementChanged || force)
        default:
            await refreshCredits(reason: .storeKitEntitlementRefresh, force: entitlementChanged || force)
        }
    }
#endif
}
