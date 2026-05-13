//
//  AISettingsView+Types.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import Foundation
import ChocofordUI
import LLMCore
import SFSafeSymbols

extension AISettingsView {
    struct DailyCreditUsage: Identifiable {
        let day: Date
        let dayLabel: String
        let amount: Double

        var id: Date { day }
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case usage
        case settings

        var id: Self { self }

        var title: String {
            switch self {
                case .usage: String(localizable: .settingsAITabUsage)
                case .settings: String(localizable: .settingsAITabSettings)
            }
        }

        var iconSymbol: SFSymbol {
            switch self {
                case .usage:
                    if #available(macOS 14.0, *) {
                        .gaugeWithDotsNeedle67percent
                    } else {
                        .arrowUpAndDownAndSparkles
                    }
                case .settings:
                    .sliderHorizontal3
            }
        }
    }

    enum ActivityGrouping: String, CaseIterable, Identifiable {
        case recent
        case file

        var id: Self { self }

        var title: String {
            switch self {
                case .recent: String(localizable: .settingsAIUsageActivityGroupingRecent)
                case .file: String(localizable: .settingsAIUsageActivityGroupingFiles)
            }
        }
    }

    struct FileActivityGroup: Identifiable {
        let fileLabel: String
        let transactions: [CreditsTransaction]
        let hasFileContext: Bool

        var id: String { fileLabel }

        var consumedCredits: Double {
            transactions.reduce(0) { partial, transaction in
                transaction.amount < 0 ? partial + abs(transaction.amount) : partial
            }
        }

        var latestTransactionDate: Date {
            transactions.first?.createdAt ?? .distantPast
        }
    }
}
