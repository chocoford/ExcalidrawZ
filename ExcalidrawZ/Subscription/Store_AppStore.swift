//
//  Store_AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI
import StoreKit
import Logging

import ChocofordUI
fileprivate typealias Transaction = StoreKit.Transaction
fileprivate typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
fileprivate typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public enum StoreError: Error {
    case failedVerification
}

enum StoreKitEntitlementRefreshReason: String, Sendable {
    case appLaunch
    case transactionUpdate
    case purchase
    case restorePurchases
    case appBecameActive
    case windowBecameKey
    case paywallPresented
    case entitlementExpirationTimer
    case coalesced
    case manual
}

// Define the app's subscription entitlements by level of service, with the highest level of service first.
// The numerical-level value matches the subscription's level that you configure in
// the StoreKit configuration file or App Store Connect.
public enum ServiceEntitlement: Int, Comparable {
    case notEntitled = 0

    case max10x = 1
    case max = 2
    case pro = 3
    case starter = 4
    
    init?(for product: Product) {
        // The product must be a subscription to have service entitlements.
        guard let subscription = product.subscription else {
            return nil
        }
        if #available(macOS 13.3, iOS 16.4, *) {
            self.init(rawValue: subscription.groupLevel)
        } else {
            switch product.id {
            case "plan.starter", "plan.starter_yearly":
                self = .starter
            case "plan.pro", "plan.pro_yearly":
                self = .pro
            case "plan.max_3x", "plan.max_3x_yearly":
                self = .max
            case "plan.max_10x", "plan.max_10x_yearly":
                self = .max10x
            default:
                self = .notEntitled
            }
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        // Subscription-group levels are in descending order.
        return lhs.rawValue > rhs.rawValue
    }
}

@MainActor
class Store: ObservableObject {
    static let shared = Store()
    
    let plans: [SubscriptionItem] = [.starter, .pro, .max, .max10x]
    
    @Published private(set) var subscriptions: [Product]
    @Published private(set) var memberships: [Product]
    
    @Published private(set) var purchasedPlans: [Product] = []
    @Published private(set) var purchasedMemberships: [Product] = []
    @Published private(set) var subscriptionGroupStatus: Product.SubscriptionInfo.Status?
    @Published private(set) var activePlanExpirationDate: Date?

#if DEBUG && !APP_STORE
    @Published var debugActiveSubscriptionItem: SubscriptionItem? = .pro
#endif

    var activeSubscriptionItem: SubscriptionItem? {
#if DEBUG && !APP_STORE
        if let debugActiveSubscriptionItem {
            return debugActiveSubscriptionItem
        }
#endif
        guard let purchasedPlan = purchasedPlans.first else { return nil }
        return plans.first { $0.containsProductID(purchasedPlan.id) }
    }
        
    var updateListenerTask: Task<Void, Error>? = nil
    private var isRefreshingEntitlements = false
    private var hasPendingEntitlementRefresh = false
    private var pendingEntitlementRefreshForce = false
    private var lastEntitlementRefreshAt: Date = .distantPast
    private let entitlementRefreshThrottleInterval: TimeInterval = 60
    private var entitlementExpirationRefreshTask: Task<Void, Never>?
    
    private let membershipIdentifiers = [
        "Membership_Lv1_Monthly",
        "Membership_Lv2_Monthly",
    ]
    private let planIdentifiers = [
        SubscriptionItem.starter.productIDs,
        SubscriptionItem.pro.productIDs,
        SubscriptionItem.max.productIDs,
        SubscriptionItem.max10x.productIDs,
    ].flatMap { $0 }
    private let logger = Logger(label: "Store")

    private init() {
        subscriptions = []
        memberships = []
        
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()

        Task {
            // During store initialization, request products from the App Store.
            await requestProducts()

            // Deliver products that the customer purchases.
            await refreshEntitlements(reason: .appLaunch, force: true)
        }
    }
    
    // Features Availability
    var collaborationRoomLimits: Int? {
        if !purchasedPlans.isEmpty || !purchasedMemberships.isEmpty {
            return nil
        }
        return 1
    }

    
    // MARK: - Store info
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // Deliver products to the user.
                    await self.refreshEntitlements(reason: .transactionUpdate, force: true)
                    
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification.")
                }
            }
        }
    }
    
    @MainActor
    func requestProducts() async {
        do {
            // Request products from the App Store using the identifiers that the `Products.plist` file defines.
            let planProducts = try await Product.products(for: planIdentifiers + membershipIdentifiers)

            var newPlans: [Product] = []
            var newMemberships: [Product] = []

            // Filter the products into categories based on their type.
            for product in planProducts {
                switch product.type {
                    case .autoRenewable:
                        if planIdentifiers.contains(product.id) {
                            newPlans.append(product)
                        } else if membershipIdentifiers.contains(product.id) {
                            newMemberships.append(product)
                        }
                    default:
                        // Ignore this product.
                        print("Unknown product.")
                }
            }

            // Sort each product category by price, lowest to highest, to update the store.
            subscriptions = sortByPrice(newPlans)
            memberships = sortByPrice(newMemberships)

        } catch {
            print("Failed product request from the App Store server. \(error)")
        }
    }
    
    func purchase(
        _ product: Product,
        handleVerifiedPurchase: ((VerificationResult<StoreKit.Transaction>) async throws -> Void)? = nil
    ) async throws -> StoreKit.Transaction? {
        // Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        
        switch result {
            case .success(let verification):
                // Check whether the transaction is verified. If it isn't,
                // this function rethrows the verification error.
                let transaction = try checkVerified(verification)

                try await handleVerifiedPurchase?(verification)
                
                // The transaction is verified. Deliver content to the user.
                await refreshEntitlements(reason: .purchase, force: true)
                
                // Always finish a transaction.
                await transaction.finish()
                
                return transaction
            case .userCancelled, .pending:
                return nil
            default:
                return nil
        }
    }

    func isPurchased(_ product: Product) async throws -> Bool {
        // Determine whether the user purchases a given product.
        switch product.type {
        case .autoRenewable:
                return purchasedPlans.contains(product) || purchasedMemberships.contains(product)
        default:
            return false
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
            case .unverified:
                // StoreKit parses the JWS, but it fails verification.
                throw StoreError.failedVerification
            case .verified(let safe):
                // The result is verified. Return the unwrapped value.
                return safe
        }
    }
    
    @MainActor
    func updateCustomerProductStatus() async {
        await refreshEntitlements(reason: .manual, force: true)
    }

    @MainActor
    func refreshEntitlements(
        reason: StoreKitEntitlementRefreshReason,
        force: Bool = false
    ) async {
        let now = Date()
        if !force {
            let elapsed = now.timeIntervalSince(lastEntitlementRefreshAt)
            guard elapsed >= entitlementRefreshThrottleInterval else {
                let remaining = max(entitlementRefreshThrottleInterval - elapsed, 0)
                logger.debug("[Store] entitlement refresh skipped reason=\(reason.rawValue) throttleRemaining=\(String(format: "%.1f", remaining))s")
                return
            }
        }

        if isRefreshingEntitlements {
            hasPendingEntitlementRefresh = true
            pendingEntitlementRefreshForce = pendingEntitlementRefreshForce || force
            logger.debug("[Store] entitlement refresh coalesced reason=\(reason.rawValue) force=\(force)")
            return
        }

        isRefreshingEntitlements = true
        lastEntitlementRefreshAt = now
        logger.info("[Store] refresh entitlements reason=\(reason.rawValue) force=\(force)")

        let previousPlanIDs = purchasedPlans.map(\.id)
        let previousMembershipIDs = purchasedMemberships.map(\.id)
        let previousExpirationDate = activePlanExpirationDate

        await loadCustomerProductStatus(reason: reason)

#if APP_STORE
        let entitlementChanged =
            previousPlanIDs != purchasedPlans.map(\.id) ||
            previousMembershipIDs != purchasedMemberships.map(\.id) ||
            previousExpirationDate != activePlanExpirationDate
        await LLMCreditsRefreshCoordinator.shared.handleStoreKitEntitlementRefresh(
            reason: reason,
            force: force,
            entitlementChanged: entitlementChanged
        )
#endif

        isRefreshingEntitlements = false

        if hasPendingEntitlementRefresh {
            let pendingForce = pendingEntitlementRefreshForce
            hasPendingEntitlementRefresh = false
            pendingEntitlementRefreshForce = false
            await refreshEntitlements(reason: .coalesced, force: pendingForce)
        }
    }

    @MainActor
    private func loadCustomerProductStatus(reason: StoreKitEntitlementRefreshReason) async {
        // var purchasedCars: [Product] = []
        var purchasedSubscriptions: [Product] = []
        var purchasedMemberships: [Product] = []
        var planTransactionsByProductID: [String: StoreKit.Transaction] = [:]
        var entitlementExpirationDates: [Date] = []
        // var purchasedNonRenewableSubscriptions: [Product] = []

        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                // Check whether the transaction is verified. If it isn’t, catch `failedVerification` error.
                let transaction = try checkVerified(result)

                // Check the `productType` of the transaction and get the corresponding product from the store.
                switch transaction.productType {
                    case .nonConsumable:
                        break
                    case .nonRenewable:
                        break
                    case .autoRenewable:
                        if let subscription = subscriptions.first(where: { $0.id == transaction.productID }) {
                            logPlanEntitlementTransaction(transaction)
                            purchasedSubscriptions.append(subscription)
                            planTransactionsByProductID[subscription.id] = transaction
                        } else if let membership = memberships.first(where: { $0.id == transaction.productID }) {
                            purchasedMemberships.append(membership)
                        }
                        if let expirationDate = transaction.expirationDate {
                            entitlementExpirationDates.append(expirationDate)
                        }
                    default:
                        break
                }
            } catch {
                self.logger.error("[Store] refresh entitlements error: \(error)")
            }
        }

        // Update the store information with the purchased products.
        // ...
        
        // Update the store information with auto-renewable subscription products.
        let sortedPurchasedPlans = sortPurchasedPlansByEntitlement(purchasedSubscriptions)
        self.purchasedPlans = sortedPurchasedPlans
        self.purchasedMemberships = purchasedMemberships
        self.activePlanExpirationDate = sortedPurchasedPlans.first.flatMap { product in
            planTransactionsByProductID[product.id]?.expirationDate
        }

        subscriptionGroupStatus = await latestPlanSubscriptionStatus()
        logPlanStatus(subscriptionGroupStatus)
        scheduleNextEntitlementExpirationRefresh(from: entitlementExpirationDates)
        
        logger.info("[Store] ----------")
        logger.info("[Store] entitlement refresh reason: \(reason.rawValue)")
        logger.info("[Store] purchased plan IDs: \(self.purchasedPlans.map(\.id).joined(separator: ",").nilIfEmpty ?? "none")")
        logger.info("[Store] purchased membership IDs: \(self.purchasedMemberships.map(\.id).joined(separator: ",").nilIfEmpty ?? "none")")
        logger.info("[Store] active plan: \(self.activeSubscriptionItem?.id ?? "none")")
        logger.info("[Store] ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
    }
    
    func sortByPrice(_ products: [Product]) -> [Product] {
        products.sorted(by: { return $0.price < $1.price })
    }

    private func subscriptionItem(forProductID productID: String?) -> SubscriptionItem? {
        plans.first { $0.containsProductID(productID) }
    }

    private func sortPurchasedPlansByEntitlement(_ products: [Product]) -> [Product] {
        products.sorted { lhs, rhs in
            let lhsItem = subscriptionItem(forProductID: lhs.id) ?? .free
            let rhsItem = subscriptionItem(forProductID: rhs.id) ?? .free

            if lhsItem == rhsItem {
                return lhs.id < rhs.id
            }
            return lhsItem > rhsItem
        }
    }

    private func scheduleNextEntitlementExpirationRefresh(from expirationDates: [Date]) {
        entitlementExpirationRefreshTask?.cancel()

        let now = Date()
        guard let nextExpiration = expirationDates
            .filter({ $0 > now })
            .min()
        else {
            entitlementExpirationRefreshTask = nil
            return
        }

        let refreshDate = nextExpiration.addingTimeInterval(1)
        let seconds = max(refreshDate.timeIntervalSinceNow, 0)
        let nanoseconds = UInt64(min(seconds, Double(UInt64.max) / 1_000_000_000) * 1_000_000_000)

        logger.info("[Store] scheduled entitlement expiration refresh at \(refreshDate.description)")

        entitlementExpirationRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshEntitlements(reason: .entitlementExpirationTimer, force: true)
        }
    }
    
    // Get a subscription's level of service using the product ID.
    func entitlement(for status: Product.SubscriptionInfo.Status) -> ServiceEntitlement {
        // If the status is expired, then the customer is not entitled.
        if status.state == .expired || status.state == .revoked {
            return .notEntitled
        }
        // Get the product associated with the subscription status.
        let productID = status.transaction.unsafePayloadValue.productID
        guard let product = subscriptions.first(where: { $0.id == productID }) else {
            return .notEntitled
        }
        // Finally, get the corresponding entitlement for this product.
        return ServiceEntitlement(for: product) ?? .notEntitled
    }

    private func latestPlanSubscriptionStatus() async -> Product.SubscriptionInfo.Status? {
        guard let subscription = subscriptions.first?.subscription else {
            logger.info("[Store] plan status unavailable: no plan products")
            return nil
        }

        do {
            let statuses = try await subscription.status
            guard !statuses.isEmpty else {
                logger.info("[Store] plan status unavailable: status count=0")
                return nil
            }
            return statuses.max { lhs, rhs in
                let lhsEntitlement = entitlement(for: lhs)
                let rhsEntitlement = entitlement(for: rhs)
                return lhsEntitlement < rhsEntitlement
            }
        } catch {
            logger.warning("[Store] plan status unavailable: \(String(describing: error))")
            return nil
        }
    }

    private func logPlanEntitlementTransaction(_ transaction: StoreKit.Transaction) {
        logger.info(
            """
            [Store] plan entitlement productID=\(transaction.productID) \
            expires=\(transaction.expirationDate?.description ?? "nil") \
            revoked=\(transaction.revocationDate?.description ?? "nil")
            """
        )
    }

    private func logPlanStatus(_ status: Product.SubscriptionInfo.Status?) {
        guard let status else {
            logger.info("[Store] plan status: none")
            return
        }

        do {
            let transaction = try checkVerified(status.transaction)
            let renewalInfo = try checkVerified(status.renewalInfo)
            logger.info(
                """
                [Store] plan status state=\(String(describing: status.state)) \
                productID=\(transaction.productID) \
                expires=\(transaction.expirationDate?.description ?? "nil") \
                autoRenewPreference=\(renewalInfo.autoRenewPreference ?? "nil") \
                willAutoRenew=\(renewalInfo.willAutoRenew) \
                expirationReason=\(String(describing: renewalInfo.expirationReason))
                """
            )
        } catch {
            logger.error("[Store] plan status failedVerification error=\(String(describing: error)) state=\(String(describing: status.state))")
        }
    }
    
    // MARK: - UI
}
