import Foundation
import LLMCore
import LLMKit

/// Billing belongs to the historical request, not the currently selected connection.
struct AIChatUsagePresentation {
    let summary: LLMUsageSummary
    let usesBYOK: Bool

    init(summary: LLMUsageSummary, fallbackUsesBYOK: Bool) {
        let chat = summary.filtered(purpose: "chat")
        let byok = chat.filtered(billingSource: .byok)
        let platform = chat.filtered(billingSource: .platform)
        usesBYOK = byok.requestCount > 0 || (platform.requestCount == 0 && fallbackUsesBYOK)
        self.summary = byok.requestCount > 0 ? byok : chat
    }

    var tokens: Usage? { usesBYOK ? summary.tokens : nil }
    var providerToolUsage: [String: Int]? { usesBYOK ? summary.providerToolUsage : nil }
    var hasProviderUsage: Bool { tokens != nil || providerToolUsage?.isEmpty == false }
    var isPartial: Bool { !summary.isComplete }
    func showsCredits(_ credits: Double) -> Bool { !usesBYOK || credits > 0 }

    /// Native row hosting only replaces a cached row when its render key changes.
    /// Account for usage/source-only updates, not just text changes.
    static func signature(for conversation: Conversation?) -> Int {
        var hasher = Hasher()
        for record in conversation?.usageSummary.requests ?? [] {
            hasher.combine(record.id)
            hasher.combine(record.generationID)
            hasher.combine(record.billingSource?.rawValue)
            hasher.combine(record.purpose)
            hasher.combine(record.isComplete)
            hasher.combine(record.tokens?.promptTokens)
            hasher.combine(record.tokens?.completionTokens)
            hasher.combine(record.tokens?.totalTokens)
            for key in (record.providerToolUsage ?? [:]).keys.sorted() {
                hasher.combine(key)
                hasher.combine(record.providerToolUsage?[key])
            }
        }
        for message in conversation?.messages ?? [] where message.citations?.isEmpty == false {
            hasher.combine(message.id)
            hasher.combine(message.citations)
        }
        return hasher.finalize()
    }
}
