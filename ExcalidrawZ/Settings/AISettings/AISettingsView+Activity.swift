//
//  AISettingsView+Activity.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI
import ChocofordUI
import LLMCore
import SFSafeSymbols

extension AISettingsView {
    @MainActor @ViewBuilder
    var activityBody: some View {
        if let error = transactionLoadError {
            Text(localizable: .settingsAIUsageActivityLoadFailTitle(error.localizedDescription))
                .font(.caption)
                .foregroundStyle(.red)
        } else if transactions.isEmpty, isLoadingTransactions {
            HStack {
                ProgressView().controlSize(.small)
                Text(localizable: .generalLoading)
                    .foregroundStyle(.secondary)
            }
        } else if transactions.isEmpty {
            Text(localizable: .settingsAIUsageActivityEmptyTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if totalTransactionCount > 0, !transactions.isEmpty {
                activityCountLabel
            }

            switch activityGrouping {
                case .recent:
                    ForEach(transactions) { tx in
                        transactionRow(tx)
                    }
                case .file:
                    if isLoadingAllTransactions, allTransactions.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(localizable: .settingsAIUsageActivityLoadingTitle)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = allTransactionLoadError {
                        Text(localizable: .settingsAIUsageActivityLoadFailTitle(error.localizedDescription))
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if fileActivityGroups.isEmpty {
                        Text(localizable: .settingsAIUsageActivityFileEmptyTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fileActivityGroups) { group in
                            fileActivityRow(group)
                        }
                    }
            }

            if activityGrouping == .recent, transactions.count < totalTransactionCount {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    if isLoadingTransactions {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(localizable: .generalLoading)
                        }
                    } else {
                        Text(localizable: .generalButtonLoadMore)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingTransactions)
            }
        }
    }

    var transactionCountLabel: some View {
        Text(
            localizable: .settingsAIUsageActivityLoadedCountLabel(transactions.count, totalTransactionCount)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    var activityCountLabel: some View {
        switch activityGrouping {
            case .recent:
                transactionCountLabel
            case .file:
                Text(localizable: .settingsAIUsageActivityFileLoadedCountLabel(fileActivityGroups.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func transactionRow(
        _ tx: CreditsTransaction,
        showsFileContext: Bool = true
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transactionTitle(tx))
                    .font(.callout)
                Text(transactionSubtitle(tx))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if showsFileContext, let fileLabel = transactionFileLabel(tx) {
                    Label(fileLabel, systemSymbol: .docText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(formatSignedAmount(tx.amount))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tx.amount >= 0 ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    func fileActivityRow(_ group: FileActivityGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemSymbol: group.hasFileContext ? .docText : .questionmarkFolder)
                .font(.body)
                .foregroundStyle(group.hasFileContext ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.fileLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(localizable: .settingsAIUsageActivityFileRequestsCountLabel(group.transactions.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(localizable: .settingsAIUsageActivityFileCreditsLabel(formatCredits(group.consumedCredits)))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    func transactionTitle(_ tx: CreditsTransaction) -> String {
        if tx.type == .consume {
            return String(localizable: .aiChatUsageTitle)
        }
        if let reason = tx.reason, !reason.isEmpty { return reason }
        switch tx.type {
            case .purchase:
                return String(localizable: .settingsAIUsageTransactionTitlePurchase)
            case .consume:
                return String(localizable: .aiChatUsageTitle)
            case .promotion:
                return String(localizable: .settingsAIUsageTransactionTitlePromotion)
            case .refund:
                return String(localizable: .settingsAIUsageTransactionTitleRefund)
            case .subscribe:
                return String(localizable: .settingsAIUsageTransactionTitleSubscription)
            case .resubscribe:
                return String(localizable: .settingsAIUsageTransactionTitleResubscribed)
            case .renewal:
                return String(localizable: .settingsAIUsageTransactionTitleRenewal)
            case .expiration:
                return String(localizable: .settingsAIUsageTransactionTitleExpired)
            case .referral:
                return String(localizable: .settingsAIUsageTransactionTitleReferral)
            case .achievement:
                return String(localizable: .settingsAIUsageTransactionTitleAchievement)
        }
    }

    func transactionSubtitle(_ tx: CreditsTransaction) -> String {
        let timestamp = tx.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard tx.type == .consume,
              let tier = transactionModelTier(tx)
        else {
            return timestamp
        }
        return String(localizable: .settingsAIUsageTransactionSubtitleWithTier(timestamp, tier))
    }

    func transactionModelTier(_ tx: CreditsTransaction) -> String? {
        guard let metadata = tx.decodedUserMetadata(as: ExcalidrawAITransactionMetadata.self) else {
            return nil
        }
        return modelTierName(for: metadata.model)
    }

    var fileActivityGroups: [FileActivityGroup] {
        let grouped = Dictionary(grouping: allTransactions.filter { $0.amount < 0 }) { transaction in
            transactionFileLabel(transaction) ?? String(localizable: .settingsAIUsageTransactionUnknownFile)
        }

        let unknownFileLabel = String(localizable: .settingsAIUsageTransactionUnknownFile)
        return grouped.map { fileLabel, transactions in
            FileActivityGroup(
                fileLabel: fileLabel,
                transactions: transactions.sorted { $0.createdAt > $1.createdAt },
                hasFileContext: fileLabel != unknownFileLabel
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasFileContext != rhs.hasFileContext {
                return lhs.hasFileContext
            }
            if lhs.latestTransactionDate != rhs.latestTransactionDate {
                return lhs.latestTransactionDate > rhs.latestTransactionDate
            }
            return lhs.fileLabel.localizedCaseInsensitiveCompare(rhs.fileLabel) == .orderedAscending
        }
    }

    func transactionFileLabel(_ tx: CreditsTransaction) -> String? {
        guard let metadata = tx.decodedUserMetadata(as: ExcalidrawAITransactionMetadata.self) else {
            return nil
        }
        if let fileName = metadata.fileName, !fileName.isEmpty {
            return fileName
        }
        if let fileID = metadata.fileID, !fileID.isEmpty {
            return String(localizable: .settingsAIUsageTransactionFileIDLabel(String(fileID.prefix(8))))
        }
        return nil
    }

    func modelTierName(for value: String) -> String {
        let model = SupportedModel(rawValue: value)
        if model.rawValue == value {
            return model.excalidrawTierName
        }

        let lowered = value.lowercased()
        if lowered.contains("opus") {
            return String(localizable: .aiChatModelTierExtraHigh)
        }
        if lowered.contains("sonnet") {
            return String(localizable: .aiChatModelTierHigh)
        }
        if lowered.contains("haiku") {
            return String(localizable: .aiChatModelTierMedium)
        }
        if lowered.contains("mini") {
            return String(localizable: .aiChatModelTierLow)
        }
        return String(localizable: .settingsAIUsageTransactionModelTierAI)
    }
}
