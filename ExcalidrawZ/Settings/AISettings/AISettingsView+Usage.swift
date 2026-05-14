//
//  AISettingsView+Usage.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI
import Charts
import ChocofordUI
import SFSafeSymbols

extension AISettingsView {
    @MainActor @ViewBuilder
    var usageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                HStack(alignment: .center, spacing: 16) {
                    usageGauge

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(localizable: .aiChatUsageTitle)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)

                            planBadge
                        }

                        Text(planSubtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 12) {
                    tabPicker

                    Button {
                        store.togglePaywall(reason: .aiInsufficientCredits)
                    } label: {
                        Label(.localizable(.generalButtonUpgrade), systemSymbol: .sparkles)
                    }
                    .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
                    .disabled(isHighestAIPlan)
                }
            }

            dailyUsageChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor @ViewBuilder
    var activityHeader: some View {
        HStack(alignment: .center) {
            Label(.localizable(.settingsAIUsageActivityTitle), systemSymbol: .chartLineUptrendXyaxis)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if !transactions.isEmpty || !allTransactions.isEmpty {
                if #available(macOS 14.0, *) {
                    Picker(
                        .localizable(.settingsAIUsageActivityGroupingTitle),
                        selection: $activityGrouping
                    ) {
                        ForEach(ActivityGrouping.allCases) { grouping in
                            Text(grouping.title).tag(grouping)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 144)
                    .buttonBorderShape(.capsule)
                    .containerShape(.capsule)
                } else {
                    Picker(
                        .localizable(.settingsAIUsageActivityGroupingTitle),
                        selection: $activityGrouping
                    ) {
                        ForEach(ActivityGrouping.allCases) { grouping in
                            Text(grouping.title).tag(grouping)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 144)
                }
            } else if totalTransactionCount > 0 {
                transactionCountLabel
            }
        }
    }

    @MainActor @ViewBuilder
    var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(.localizable(.settingsAITitle), systemSymbol: .sliderHorizontal3)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(localizable: .settingsAISubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                tabPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor @ViewBuilder
    var usageGauge: some View {
        let metrics = usageMetrics
        SemiCircularUsageGauge(
            fraction: metrics.fractionRemaining,
            percentageText: metrics.fractionRemaining.formatted(.percent.precision(.fractionLength(0))),
            detailText: String(localizable: .settingsAIUsageRemainingText(formatCredits(metrics.remaining)))
        )
        .frame(width: 176, height: 106)
    }

    @MainActor @ViewBuilder
    var dailyUsageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localizable: .settingsAIUsageDailyChartTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if isLoadingAllTransactions {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text(localizable: .settingsAIUsageDailyChartLoadingLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if allTransactionLoadError != nil {
                    Text(localizable: .settingsAIUsageDailyChartUnavailableLabel)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(localizable: .settingsAIUsageDailyChartPeriodCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(dailyCreditUsage) { item in
                BarMark(
                    x: .value(.localizable(.settingsAIUsageDailyChartXTitle), item.dayLabel),
                    y: .value(.localizable(.settingsAIUsageDailyChartYTitle), item.amount)
                )
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(centered: true)
                }
            }
            .frame(height: 120)
        }
    }

    @ViewBuilder
    var planBadge: some View {
        Text(planName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .aiSettingsGlassCapsule(
                tint: isPaidPlan ? Color.accentColor : Color.secondary,
                isInteractive: false
            )
    }

    var isPaidPlan: Bool {
        llmState.creditsInfo?.subscription != nil
    }

    var isHighestAIPlan: Bool {
        store.activeSubscriptionItem == .max10x
    }

    var planName: String {
        // TODO: real tier-name mapping from `SubscriptionInfo` once the
        // backend ships it. Two-state mock for now.
        isPaidPlan
        ? String(localizable: .settingsAIUsagePlanProName)
        : String(localizable: .settingsAIUsagePlanFreeName)
    }

    var planSubtitle: String {
        guard let sub = llmState.creditsInfo?.subscription else {
            return String(localizable: .settingsAIUsagePlanFreeSubtitle)
        }
        let used = formatCredits(sub.usedQuota)
        let total = formatCredits(sub.monthlyQuota)
        let renew = sub.renewalDate.formatted(date: .abbreviated, time: .omitted)
        return String(localizable: .settingsAIUsagePlanSubscriptionSubtitle(used, total, renew))
    }

    var usageMetrics: (remaining: Double, total: Double, fractionRemaining: Double) {
        if let sub = llmState.creditsInfo?.subscription {
            let total = max(sub.monthlyQuota, 1)
            let remaining = min(max(sub.monthlyQuota - sub.usedQuota, 0), total)
            return (remaining, total, remaining / total)
        }

        let balance = max(llmState.creditsInfo?.balance ?? 0, 0)
        let total = max(balance, 1)
        return (balance, total, balance > 0 ? 1 : 0)
    }

    var dailyCreditUsage: [DailyCreditUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let consumedByDay = Dictionary(grouping: allTransactions.filter { $0.amount < 0 }) {
            calendar.startOfDay(for: $0.createdAt)
        }.mapValues { entries in
            entries.reduce(0) { $0 + abs($1.amount) }
        }

        return days.map { day in
            DailyCreditUsage(
                day: day,
                dayLabel: day.formatted(.dateTime.weekday(.abbreviated)),
                amount: consumedByDay[day] ?? 0
            )
        }
    }
}
