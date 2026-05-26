//
//  AISettingsView+Loading.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import Foundation
import LLMKit
import LLMCore

extension AISettingsView {
    func formatCredits(_ value: Double) -> String {
        // Credits are server-side `Double` but typically integral; show
        // fractional digits only when there's actually a fractional part.
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    func formatSignedAmount(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + formatCredits(value)
    }

    func loadInitialTransactions() async {
        guard transactions.isEmpty, !isLoadingTransactions else { return }
        await loadPage(1)
    }

    func loadNextPage() async {
        guard !isLoadingTransactions else { return }
        await loadPage(loadedPage + 1)
    }

    @MainActor
    func loadAllTransactionsIfNeeded() async {
        guard allTransactions.isEmpty, !isLoadingAllTransactions else { return }
        isLoadingAllTransactions = true
        allTransactionLoadError = nil
        defer { isLoadingAllTransactions = false }

        do {
            var page = 1
            var collected: [CreditsTransaction] = []
            var totalCount = 0

            repeat {
                let history = try await LLMClient.shared.getTransactionHistory(
                    page: page,
                    pageSize: aggregatePageSize,
                    type: nil
                )
                totalCount = history.totalCount
                collected.append(contentsOf: history.transactions)

                guard !history.transactions.isEmpty else { break }
                page += 1
            } while collected.count < totalCount

            allTransactions = collected
            allTransactionCount = totalCount
            debugLogTransactionMetadata(collected, source: "all-transactions")
        } catch {
            allTransactionLoadError = error
        }
    }

    @MainActor
    func loadPage(_ page: Int) async {
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
            debugLogTransactionMetadata(history.transactions, source: "page-\(page)")
        } catch {
            transactionLoadError = error
        }
    }

    func debugLogTransactionMetadata(
        _ transactions: [CreditsTransaction],
        source: String
    ) {
#if DEBUG
        print("[AISettings] \(source) metadata dump: \(transactions.count) transaction(s)")
        for (index, tx) in transactions.enumerated() {
            print(
                "[AISettings] tx[\(index)] type=\(tx.type) amount=\(tx.amount) createdAt=\(tx.createdAt) metadata=\(debugMetadataDescription(for: tx))"
            )
        }
#endif
    }

    func debugMetadataDescription(for tx: CreditsTransaction) -> String {
#if DEBUG
        let directMetadata = tx.metadata?.description ?? "<nil>"
        let userMetadata = tx.decodedUserMetadata(as: ExcalidrawAITransactionMetadata.self)
            .map { String(describing: $0) } ?? "<nil>"
        let context = tx.chatContext().map { String(describing: $0) } ?? "<nil>"
        let usage = tx.usage().map { String(describing: $0) } ?? "<nil>"
        let deductionSources = tx.deductionSources().map { String(describing: $0) } ?? "<nil>"

        return [
            "raw=\(directMetadata)",
            "userInfo=\(userMetadata)",
            "context=\(context)",
            "usage=\(usage)",
            "deductionSources=\(deductionSources)"
        ].joined(separator: " | ")
#else
        return ""
#endif
    }
}
