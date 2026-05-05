//
//  AISettingsView.swift
//  ExcalidrawZ
//
//  Aggregates AI-related state into one Settings tab.
//
//  Layout:
//   - The first (and only) section's *header* is a custom hero block —
//     prominent credits balance, plan badge + subtitle, Top-up / Manage
//     buttons. Putting it in the header lets the body host just the
//     transaction list without competing for visual weight.
//   - The section's *body* is the activity log paginated through
//     `LLMClient.getTransactionHistory(...)`.
//
//  Subscription naming ("Free" / "Pro") is mocked — we don't have a tier-name
//  mapping from `SubscriptionInfo` yet. Swap `planName(for:)` when the
//  backend ships that.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore

struct AISettingsView: View {
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var store: Store

    @State private var transactions: [CreditsTransaction] = []
    @State private var totalTransactionCount: Int = 0
    @State private var loadedPage: Int = 0
    @State private var isLoadingTransactions: Bool = false
    @State private var transactionLoadError: Error?

    private let pageSize: Int = 20

    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Form {
                Section {
                    activityBody
                } header: {
                    creditsHeader
                        .textCase(nil)            // override Form's uppercase
                        .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .task { await loadInitialTransactions() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    creditsHeader
                    Divider()
                    activityBody
                }
                .padding()
            }
            .task { await loadInitialTransactions() }
        }
    }

    // MARK: - Credits + plan hero (section header)

    @MainActor @ViewBuilder
    private var creditsHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            balanceRow
            planRow
        }
    }

    /// Top of the hero: large balance number on the left, primary action on
    /// the right. Loading skeleton while `creditsInfo` is nil so the layout
    /// doesn't jump when the publisher fires.
    @ViewBuilder
    private var balanceRow: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Credits remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let balance = llmState.creditsInfo?.balance {
                    Text(formatCredits(balance))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                store.togglePaywall(reason: .aiInsufficientCredits)
            } label: {
                Label("Top up", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// Plan badge + subtitle (used / total this month, renewal date) + a
    /// secondary "Manage" entry. For free users the subtitle is a soft
    /// upsell line.
    @ViewBuilder
    private var planRow: some View {
        HStack(alignment: .center, spacing: 8) {
            planBadge

            Text(planSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Manage") {
                store.togglePaywall(reason: .aiInsufficientCredits)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var planBadge: some View {
        Text(planName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(isPaidPlan ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
            }
    }

    private var isPaidPlan: Bool {
        llmState.creditsInfo?.subscription != nil
    }

    private var planName: String {
        // TODO: real tier-name mapping from `SubscriptionInfo` once the
        // backend ships it. Two-state mock for now.
        isPaidPlan ? "Pro" : "Free"
    }

    private var planSubtitle: String {
        guard let sub = llmState.creditsInfo?.subscription else {
            return "Upgrade for a higher monthly quota."
        }
        let used = formatCredits(sub.usedQuota)
        let total = formatCredits(sub.monthlyQuota)
        let renew = sub.renewalDate.formatted(date: .abbreviated, time: .omitted)
        return "\(used) / \(total) this month · renews \(renew)"
    }

    // MARK: - Activity list (section body)

    @MainActor @ViewBuilder
    private var activityBody: some View {
        if let error = transactionLoadError {
            Text("Couldn't load activity: \(error.localizedDescription)")
                .font(.caption)
                .foregroundStyle(.red)
        } else if transactions.isEmpty, isLoadingTransactions {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
        } else if transactions.isEmpty {
            Text("No activity yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(transactions) { tx in
                transactionRow(tx)
            }
            if transactions.count < totalTransactionCount {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    if isLoadingTransactions {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading…")
                        }
                    } else {
                        Text("Load more")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingTransactions)
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: CreditsTransaction) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transactionTitle(tx))
                    .font(.callout)
                Text(tx.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatSignedAmount(tx.amount))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tx.amount >= 0 ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }

    private func transactionTitle(_ tx: CreditsTransaction) -> String {
        if let reason = tx.reason, !reason.isEmpty { return reason }
        switch tx.type {
        case .purchase: return "Purchase"
        case .consume: return "AI usage"
        case .promotion: return "Promotion"
        case .refund: return "Refund"
        case .subscribe: return "Subscription"
        case .resubscribe: return "Resubscribed"
        case .renewal: return "Renewal"
        case .expiration: return "Expired"
        case .referral: return "Referral"
        case .achievement: return "Achievement"
        }
    }

    // MARK: - Formatting

    private func formatCredits(_ value: Double) -> String {
        // Credits are server-side `Double` but typically integral; show
        // fractional digits only when there's actually a fractional part.
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func formatSignedAmount(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + formatCredits(value)
    }

    // MARK: - Data loading

    private func loadInitialTransactions() async {
        guard transactions.isEmpty, !isLoadingTransactions else { return }
        await loadPage(1)
    }

    private func loadNextPage() async {
        guard !isLoadingTransactions else { return }
        await loadPage(loadedPage + 1)
    }

    @MainActor
    private func loadPage(_ page: Int) async {
        isLoadingTransactions = true
        transactionLoadError = nil
        defer { isLoadingTransactions = false }
        do {
            let history = try await LLMClient.shared.getTransactionHistory(
                page: page,
                pageSize: pageSize,
                type: nil
            )
            // Replace on first page so a manual refresh wouldn't accumulate
            // duplicates; append on subsequent pages.
            if page == 1 {
                transactions = history.transactions
            } else {
                transactions.append(contentsOf: history.transactions)
            }
            totalTransactionCount = history.totalCount
            loadedPage = page
        } catch {
            transactionLoadError = error
        }
    }
}
