//
//  SubscriptionState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI
import StoreKit
import os.log

fileprivate typealias Transaction = StoreKit.Transaction
fileprivate typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
fileprivate typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

public enum StoreError: Error {
    case failedVerification
}

struct SubscriptionItem: Hashable, Identifiable, Comparable {
    static let free = SubscriptionItem(
        id: "free",
        title: "Free",
        // 免费的计划，可以享受绝大部分的功能
        description: "Enjoy most of the app's powerful features for free. Perfect for personal use and occasional collaboration.",
        features: [
            "Unlimited draws",
            "iCloud sync data",
            "Lossless PDF export",
            "Libraries",
            "Collaborate with **1** room."
        ]
    )
    
    static let starter = SubscriptionItem(
        id: "plan.starter",
        title: "Starter",
        // 基础计划，提供基础付费功能，收费方面也很低——$0.99，主要用来cover成本
        description: "Unlock essential premium features ideal for regular collaborators at a minimal price. Helping cover the operational costs.",
        features: [
            "Unlimited draws",
            "iCloud sync data",
            "Lossless PDF export",
            "Libraries",
            "Collaborate with **3** room."
        ]
    )
    
    static let pro = SubscriptionItem(
        id: "plan.pro",
        title: "Pro",
        // 无限制
        description: "Experience limitless collaboration and advanced features. Designed for professionals and teams with extensive collaborative needs.",
        features: [
            "Unlimited draws",
            "iCloud sync data",
            "Lossless PDF export",
            "Libraries",
            "Collaborate with **unlimited** room."
        ]
    )
    var id: String
    var title: String
    var description: String
    var features: [String]
    
    static func < (lhs: SubscriptionItem, rhs: SubscriptionItem) -> Bool {
        if lhs == rhs { return false }
        if lhs == .free {
            return true
        }
        if lhs == .starter {
            return rhs != .free
        }
        if lhs == .pro {
            return false
        }
        return false
    }
    
}

// Define the app's subscription entitlements by level of service, with the highest level of service first.
// The numerical-level value matches the subscription's level that you configure in
// the StoreKit configuration file or App Store Connect.
public enum ServiceEntitlement: Int, Comparable {
    case notEntitled = 0
    
    case pro = 1
    case starter = 2
    
    init?(for product: Product) {
        // The product must be a subscription to have service entitlements.
        guard let subscription = product.subscription else {
            return nil
        }
        if #available(macOS 13.3, iOS 16.4, *) {
            self.init(rawValue: subscription.groupLevel)
        } else {
            switch product.id {
            case "plan.starter":
                self = .starter
            case "plan.pro":
                self = .pro
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

class Store: ObservableObject {
    
    let plans: [SubscriptionItem] = [.free, .starter, .pro]
    
    @Published private(set) var subscriptions: [Product]
    @Published private(set) var memberships: [Product]
    
    @Published private(set) var purchasedPlans: [Product] = []
    @Published private(set) var purchasedMemberships: [Product] = []
    @Published private(set) var subscriptionGroupStatus: Product.SubscriptionInfo.Status?
        
    var updateListenerTask: Task<Void, Error>? = nil
    
    private let membershipIdentifiers = [
        "Membership_Lv1_Monthly",
        "Membership_Lv2_Monthly",
    ]
    private let planIdentifiers = [
        SubscriptionItem.starter.id,
        SubscriptionItem.pro.id,
    ]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Store")

    init() {
        subscriptions = []
        memberships = []
        
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()

        Task {
            // During store initialization, request products from the App Store.
            await requestProducts()

            // Deliver products that the customer purchases.
            await updateCustomerProductStatus()
        }
    }
    
    // Features Availability
    var collaborationRoomLimits: Int? {
        if purchasedPlans.contains(where: {$0.id == SubscriptionItem.pro.id}) || !purchasedMemberships.isEmpty {
            return nil
        } else if purchasedPlans.contains(where: {$0.id == SubscriptionItem.starter.id})  {
             return 3
        }
        return 1
    }

    
    // MARK: - Store info
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Deliver products to the user.
                    await self.updateCustomerProductStatus()
                    
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
    
    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        // Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        
        switch result {
            case .success(let verification):
                // Check whether the transaction is verified. If it isn't,
                // this function rethrows the verification error.
                let transaction = try checkVerified(verification)
                
                // The transaction is verified. Deliver content to the user.
                await updateCustomerProductStatus()
                
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
        // var purchasedCars: [Product] = []
        var purchasedSubscriptions: [Product] = []
        var purchasedMemberships: [Product] = []
        // var purchasedNonRenewableSubscriptions: [Product] = []

        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            self.logger.debug("[Store] currentEntitlements: \(String(describing: result))")
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
                            purchasedSubscriptions.append(subscription)
                        } else if let membership = memberships.first(where: { $0.id == transaction.productID }) {
                            purchasedMemberships.append(membership)
                        }
                    default:
                        break
                }
            } catch {
                self.logger.error("[Store] updateCustomerProductStatus error: \(error)")
            }
        }

        // Update the store information with the purchased products.
        // ...
        
        // Update the store information with auto-renewable subscription products.
        self.purchasedPlans = purchasedSubscriptions
        self.purchasedMemberships = purchasedMemberships

        // Check the `subscriptionGroupStatus` to learn the auto-renewable subscription state to determine whether the customer
        // is new (never subscribed), active, or inactive (expired subscription).
        // This app has only one subscription group, so products in the subscriptions array all belong to the same group.
        // Customers can be subscribed to only one product in the subscription group.
        // The statuses that `product.subscription.status` returns apply to the entire subscription group.
        subscriptionGroupStatus = try? await subscriptions.first?.subscription?.status.max { lhs, rhs in
            // There may be multiple statuses for different family members, because this app supports Family Sharing.
            // The subscriber is entitled to service for the status with the highest level of service.
            let lhsEntitlement = entitlement(for: lhs)
            let rhsEntitlement = entitlement(for: rhs)
            return lhsEntitlement < rhsEntitlement
        }
        
        logger.info("[Store] ----------")
        logger.info("[Store] purchased plans: \(String(describing: self.purchasedPlans))")
        logger.info("[Store] purchased memberships: \(String(describing: self.purchasedMemberships))")
        logger.info("[Store] ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
    }
    
    func sortByPrice(_ products: [Product]) -> [Product] {
        products.sorted(by: { return $0.price < $1.price })
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
    
    // MARK: - UI
    @Published var isPaywallPresented = false
    @Published private(set) var reachPaywallReason: ReachPaywallReason?

    enum ReachPaywallReason {
        case roomLimit
        
        var description: String {
            switch self {
                case .roomLimit:
                    "You’ve reached the maximum number of collaborative rooms limitation in current Plan."
            }
        }
    }
    
    func togglePaywall(reason: ReachPaywallReason) {
        self.reachPaywallReason = reason
        self.isPaywallPresented.toggle()
    }
    
}


