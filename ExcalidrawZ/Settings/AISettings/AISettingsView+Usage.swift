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
    @ViewBuilder
    var usageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsTabHeader {
                usageSummary
            } accessory: {
                Button {
                    presentPaywall(reason: .aiInsufficientCredits)
                } label: {
                    Label(.localizable(.generalButtonUpgrade), systemSymbol: .sparkles)
                }
                .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
                .disabled(isHighestAIPlan)
            }

            dailyUsageChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var usageSummary: some View {
        if usesCompactSettingsLayout {
            VStack(alignment: .leading, spacing: 12) {
                usageGauge
                usagePlanText
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    usageGauge
                    usagePlanText
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 12) {
                    usageGauge
                    usagePlanText
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var usagePlanText: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(localizable: .aiChatUsageTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    planBadge
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(localizable: .aiChatUsageTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    planBadge
                }
            }

            Text(planSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    var activityHeader: some View {
        if usesCompactSettingsLayout {
            VStack(alignment: .leading, spacing: 10) {
                Label(.localizable(.settingsAIUsageActivityTitle), systemSymbol: .chartLineUptrendXyaxis)
                    .font(.headline)
                    .foregroundStyle(.primary)

                activityGroupingControl
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    Label(.localizable(.settingsAIUsageActivityTitle), systemSymbol: .chartLineUptrendXyaxis)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 16)

                    activityGroupingControl
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 10) {
                    Label(.localizable(.settingsAIUsageActivityTitle), systemSymbol: .chartLineUptrendXyaxis)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    activityGroupingControl
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var activityGroupingControl: some View {
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

    @ViewBuilder
    var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsTabHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Label(.localizable(.settingsAITitle), systemSymbol: .sliderHorizontal3)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(localizable: .settingsAISubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var usageGauge: some View {
        let metrics = usageMetrics
        SemiCircularUsageGauge(
            fraction: metrics.fractionRemaining,
            percentageText: metrics.fractionRemaining.formatted(.percent.precision(.fractionLength(0))),
            detailText: String(localizable: .settingsAIUsageRemainingText(formatCredits(metrics.remaining)))
        )
        .frame(
            width: usesCompactSettingsLayout ? 156 : 176,
            height: usesCompactSettingsLayout ? 96 : 106
        )
    }

    @ViewBuilder
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
        store.activeSubscriptionItem != nil
    }

    var isHighestAIPlan: Bool {
        store.activeSubscriptionItem == .max10x
    }

    var planName: String {
        store.activeSubscriptionItem?.title
        ?? String(localizable: .settingsAIUsagePlanFreeName)
    }

    var planSubtitle: String {
        guard let periodicCredits = llmState.creditsInfo?.periodicCredits else {
            return String(localizable: .settingsAIUsagePlanFreeSubtitle)
        }
        let used = formatCredits(periodicCredits.used)
        let total = formatCredits(periodicCredits.quota)
        let reset = periodicCredits.resetDate.formatted(date: .abbreviated, time: .omitted)
        return String(localizable: .settingsAIUsagePlanSubscriptionSubtitle(used, total, reset))
    }

    var usageMetrics: (remaining: Double, total: Double, fractionRemaining: Double) {
        guard let creditsInfo = llmState.creditsInfo else {
            return (0, 1, 0)
        }

        let balance = max(creditsInfo.balance, 0)

        if let periodicCredits = creditsInfo.periodicCredits {
            let total = max(
                periodicCredits.quota + max(creditsInfo.purchasedCredits, 0),
                balance,
                1
            )
            return (balance, total, balance > 0 ? min(balance / total, 1) : 0)
        }

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
