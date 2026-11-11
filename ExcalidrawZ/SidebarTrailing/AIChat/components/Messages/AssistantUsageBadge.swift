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
                            Text(String(format: String(localized: "AI.Usage.tokens"), compact(tokens.totalTokens)))
                            if presentation.isPartial { Text(String(localized: "AI.Usage.partial")) }
                        }
                        if let searches = presentation.providerToolUsage?["web_search_requests"] {
                            Image(systemName: "magnifyingglass")
                            Text(String(format: String(localized: "AI.Usage.searches"), compact(searches)))
                        } else if presentation.tokens == nil {
                            Label(String(localized: "AI.Usage.providerTools"), systemImage: "wrench")
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
                .help(String(localized: "AI.Usage.platformCredits"))
            }
        }
    }

    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    private var tooltip: String {
        var lines: [String] = []
        if let tokens = presentation.tokens {
            lines.append(String(format: String(localized: "AI.Usage.tooltip"),
                tokens.promptTokens.formatted(), tokens.completionTokens.formatted(), tokens.totalTokens.formatted()))
            if presentation.isPartial { lines.append(String(localized: "AI.Usage.partialDescription")) }
        }
        if presentation.providerToolUsage?.isEmpty == false { lines.append(String(localized: "AI.Usage.providerToolsDescription")) }
        return lines.joined(separator: "\n")
    }

    private var usageDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "AI.Usage.providerTitle")).font(.headline)
            if let tokens = presentation.tokens {
                detail(String(localized: "AI.Usage.input"), tokens.promptTokens)
                detail(String(localized: "AI.Usage.output"), tokens.completionTokens)
                detail(String(localized: "AI.Usage.total"), tokens.totalTokens)
            }
            detail(String(localized: "AI.Usage.requests"), presentation.summary.requestCount)
            if let counters = presentation.providerToolUsage, !counters.isEmpty {
                Text(String(localized: "AI.Usage.providerTools")).font(.subheadline).padding(.top, 4)
                ForEach(counters.keys.sorted(), id: \.self) { key in
                    if let count = counters[key] {
                        detail(key == "web_search_requests" ? String(localized: "AI.Usage.providerSearches") : key, count)
                    }
                }
                Text(String(localized: "AI.Usage.providerToolsDescription"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if presentation.isPartial {
                if presentation.summary.unreportedRequestCount > 0 {
                    detail(String(localized: "AI.Usage.unreported"), presentation.summary.unreportedRequestCount)
                }
                if presentation.summary.incompleteRequestCount > 0 {
                    detail(String(localized: "AI.Usage.incomplete"), presentation.summary.incompleteRequestCount)
                }
                Text(String(localized: "AI.Usage.partialDescription"))
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
