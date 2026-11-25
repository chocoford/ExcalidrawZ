import SwiftUI
import LLMCore
import LLMKit

private struct AIChatUsesBYOKKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AIChatUsageConversationKey: EnvironmentKey {
    static let defaultValue: Conversation? = nil
}

extension EnvironmentValues {
    var aiChatUsesBYOK: Bool {
        get { self[AIChatUsesBYOKKey.self] }
        set { self[AIChatUsesBYOKKey.self] = newValue }
    }
    var aiChatUsageConversation: Conversation? {
        get { self[AIChatUsageConversationKey.self] }
        set { self[AIChatUsageConversationKey.self] = newValue }
    }
}

struct AssistantUsageBadge: View {
    @Environment(\.aiChatUsesBYOK) private var usesBYOK
    @Environment(\.aiChatUsageConversation) private var conversation
    let credits: Double
    let sourceID: String
    @State private var showsDetails = false

    private var presentation: AIChatUsagePresentation {
        .init(summary: conversation?.usageSummary(forMessageID: sourceID) ?? .init([]), fallbackUsesBYOK: usesBYOK)
    }

    var body: some View {
        HStack(spacing: 6) {
            if presentation.hasProviderUsage {
                Button { showsDetails = true } label: {
                    HStack(spacing: 4) {
                        if let tokens = presentation.tokens {
                            Image(systemName: "number")
                            Text(.localizable(.aIUsageTokens(compact(tokens.totalTokens))))
                            if presentation.isPartial { Text(.localizable(.aIUsagePartial)) }
                        }
                        if let searches = presentation.providerToolUsage?["web_search_requests"] {
                            Image(systemName: "magnifyingglass")
                            Text(.localizable(.aIUsageSearches(compact(searches))))
                        } else if presentation.tokens == nil {
                            Label(.localizable(.aIUsageProviderTools), systemImage: "wrench")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .usageBadgeSurface()
                }
                .buttonStyle(.plain)
                .help(tooltip)
                .popover(isPresented: $showsDetails) { usageDetails }
            }
            if presentation.showsCredits(credits) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.circle")
                    Text(credits.formatted(.number.precision(.fractionLength(2))))
                }
                .usageBadgeSurface()
                .help(String(localizable: .aIUsagePlatformCredits))
            }
        }
    }

    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    private var tooltip: String {
        var lines: [String] = []
        if let tokens = presentation.tokens {
            lines.append(String(localizable: .aIUsageTooltip(
                tokens.promptTokens.formatted(), tokens.completionTokens.formatted(), tokens.totalTokens.formatted())))
            if presentation.isPartial { lines.append(String(localizable: .aIUsagePartialDescription)) }
        }
        if presentation.providerToolUsage?.isEmpty == false { lines.append(String(localizable: .aIUsageProviderToolsDescription)) }
        return lines.joined(separator: "\n")
    }

    private var usageDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.localizable(.aIUsageProviderTitle)).font(.headline)
            if let tokens = presentation.tokens {
                detail(String(localizable: .aIUsageInput), tokens.promptTokens)
                detail(String(localizable: .aIUsageOutput), tokens.completionTokens)
                detail(String(localizable: .aIUsageTotal), tokens.totalTokens)
            }
            detail(String(localizable: .aIUsageRequests), presentation.summary.requestCount)
            if let counters = presentation.providerToolUsage, !counters.isEmpty {
                Text(.localizable(.aIUsageProviderTools)).font(.subheadline).padding(.top, 4)
                ForEach(counters.keys.sorted(), id: \.self) { key in
                    if let count = counters[key] {
                        detail(key == "web_search_requests" ? String(localizable: .aIUsageProviderSearches) : key, count)
                    }
                }
                Text(.localizable(.aIUsageProviderToolsDescription))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if presentation.isPartial {
                if presentation.summary.unreportedRequestCount > 0 {
                    detail(String(localizable: .aIUsageUnreported), presentation.summary.unreportedRequestCount)
                }
                if presentation.summary.incompleteRequestCount > 0 {
                    detail(String(localizable: .aIUsageIncomplete), presentation.summary.incompleteRequestCount)
                }
                Text(.localizable(.aIUsagePartialDescription))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 260)
        .textSelection(.enabled)
    }

    private func detail(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.formatted()).monospacedDigit()
        }
        .font(.callout)
    }
}

private extension View {
    func usageBadgeSurface() -> some View {
        font(.footnote).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background { Capsule().fill(.regularMaterial) }
    }
}
