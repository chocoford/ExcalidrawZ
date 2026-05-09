//
//  AISettingsView.swift
//  ExcalidrawZ
//
//  Aggregates AI-related state into one Settings tab.
//
//  Layout:
//   - Usage: custom section header with tab controls, remaining-credit Gauge,
//     and quota details. Body shows recent activity or file-level usage.
//   - Settings: custom section header with tab controls and title. Body is
//     only the AI defaults.
//
//  Subscription naming ("Free" / "Pro") is mocked — we don't have a tier-name
//  mapping from `SubscriptionInfo` yet. Swap `planName(for:)` when the
//  backend ships that.
//

import SwiftUI
import Charts
import ChocofordUI
import LLMKit
import LLMCore

struct AISettingsView: View {
    private struct DailyCreditUsage: Identifiable {
        let day: Date
        let dayLabel: String
        let amount: Double

        var id: Date { day }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case usage
        case settings

        var id: Self { self }

        var title: String {
            switch self {
                case .usage: "Usage"
                case .settings: "Settings"
            }
        }

        var iconName: String {
            switch self {
                case .usage: "gauge.with.dots.needle.67percent"
                case .settings: "slider.horizontal.3"
            }
        }
    }

    private enum ActivityGrouping: String, CaseIterable, Identifiable {
        case recent
        case file

        var id: Self { self }

        var title: String {
            switch self {
                case .recent: "Recent"
                case .file: "Files"
            }
        }
    }

    private struct FileActivityGroup: Identifiable {
        let fileLabel: String
        let transactions: [CreditsTransaction]
        let hasFileContext: Bool

        var id: String { fileLabel }
        var consumedCredits: Double {
            transactions.reduce(0) { partial, transaction in
                transaction.amount < 0 ? partial + abs(transaction.amount) : partial
            }
        }
    }

    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var store: Store
    @ObservedObject private var prefs = AIChatPreferences.shared

    @State private var selectedTab: SettingsTab = .usage
    @State private var activityGrouping: ActivityGrouping = .recent
    @State private var transactions: [CreditsTransaction] = []
    @State private var totalTransactionCount: Int = 0
    @State private var loadedPage: Int = 0
    @State private var isLoadingTransactions: Bool = false
    @State private var transactionLoadError: Error?
    @State private var allTransactions: [CreditsTransaction] = []
    @State private var allTransactionCount: Int = 0
    @State private var isLoadingAllTransactions: Bool = false
    @State private var allTransactionLoadError: Error?

    /// Model list for the Default Model picker, sourced from the agent's
    /// `allowedModels`. Loaded lazily on first appearance so opening
    /// Settings doesn't pay a network cost up-front.
    @State private var availableModels: [SupportedModel] = []

    private let pageSize: Int = 20
    private let aggregatePageSize: Int = 100
    private let tabPickerWidth: CGFloat = 156
    private let tabPickerHeight: CGFloat = 32
    private let tabSegmentWidth: CGFloat = 74
    private let tabSegmentHeight: CGFloat = 26
    private let agentID = "excalidraw-canvas"

    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Form {
                selectedTabContent
            }
            .formStyle(.grouped)
            .task { await loadInitialTransactions() }
            .task { await loadAllTransactionsIfNeeded() }
            .task { await loadAvailableModelsIfNeeded() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectedTabContent
                }
                .padding()
            }
            .task { await loadInitialTransactions() }
            .task { await loadAllTransactionsIfNeeded() }
            .task { await loadAvailableModelsIfNeeded() }
        }
    }

    @ViewBuilder
    private var tabPicker: some View {
        SwiftUI.Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    tabButtons
                }
            } else {
                tabButtons
            }
        }
    }

    @ViewBuilder
    private var tabButtons: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(width: 72, height: 26)
                    .foregroundStyle(
                        selectedTab == tab ? Color.primary : Color.secondary
                    )
                    .background {
                        Capsule()
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        }
    }

    @MainActor @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
            case .usage:
                Section {
                    activityBody
                } header: {
                    VStack(spacing: 10) {
                        usageHeader
                            .textCase(nil)
                        
                        activityHeader
                    }
                }
            case .settings:
                Section {
                    defaultModelPicker
                } header: {
                    settingsHeader
                        .textCase(nil)
                }
        }
    }

    // MARK: - Default model picker

    /// Picker for `prefs.defaultModel`. Bound through rawValue so the
    /// underlying `SupportedModel` enum doesn't need explicit Hashable
    /// conformance for the Picker tag matching. List is the agent's
    /// allowed models with the user's current pick spliced in if it
    /// somehow isn't there (e.g., backend dropped a model from the
    /// allowed list after the user already picked it).
    @ViewBuilder
    private var defaultModelPicker: some View {
        let current = prefs.defaultModel
        let mergedModels: [SupportedModel] = {
            if availableModels.isEmpty { return [current] }
            if availableModels.contains(where: { $0.rawValue == current.rawValue }) {
                return availableModels
            }
            return [current] + availableModels
        }()

        Picker("Default model", selection: Binding(
            get: { prefs.defaultModel.rawValue },
            set: { prefs.defaultModel = SupportedModel(rawValue: $0) }
        )) {
            ForEach(mergedModels, id: \.rawValue) { model in
                Text(model.excalidrawTierName).tag(model.rawValue)
            }
        }
        .help("Used for new conversations and as the picker default. Each conversation can override this from its own model picker.")
    }

    private func loadAvailableModelsIfNeeded() async {
        guard availableModels.isEmpty else { return }
        do {
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.availableModels = config.allowedModels
            }
        } catch {
            // Silently keep the picker showing just the current selection.
            // The user can still change it later when network recovers.
        }
    }

    // MARK: - Usage header

    @MainActor @ViewBuilder
    private var usageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                HStack(alignment: .center, spacing: 16) {
                    usageGauge

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("AI Usage")
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
                        Label("Upgrade", systemImage: "sparkles")
                    }
                    .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
                }
            }

             dailyUsageChart

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor @ViewBuilder
    private var activityHeader: some View {
        HStack(alignment: .center) {
            Label("Activity", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if !transactions.isEmpty || !allTransactions.isEmpty {
                if #available(macOS 14.0, *) {
                    Picker("Activity View", selection: $activityGrouping) {
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
                    Picker("Activity View", selection: $activityGrouping) {
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
    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI Settings", systemImage: "slider.horizontal.3")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Choose the defaults AI Chat uses when starting or regenerating conversations.")
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
    private var usageGauge: some View {
        let metrics = usageMetrics
        SemiCircularUsageGauge(
            fraction: metrics.fractionRemaining,
            percentageText: metrics.fractionRemaining.formatted(.percent.precision(.fractionLength(0))),
            detailText: "\(formatCredits(metrics.remaining)) left"
        )
        .frame(width: 176, height: 106)
    }

    @MainActor @ViewBuilder
    private var dailyUsageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily credits")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if isLoadingAllTransactions {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("Loading full history")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if allTransactionLoadError != nil {
                    Text("Full history unavailable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(dailyCreditUsage) { item in
                BarMark(
                    x: .value("Day", item.dayLabel),
                    y: .value("Credits", item.amount)
                )
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(centered: true)
                }
            }
            .frame(height: 120)
        }
    }

    @ViewBuilder
    private var planBadge: some View {
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

    private var usageMetrics: (remaining: Double, total: Double, fractionRemaining: Double) {
        if let sub = llmState.creditsInfo?.subscription {
            let total = max(sub.monthlyQuota, 1)
            let remaining = min(max(sub.monthlyQuota - sub.usedQuota, 0), total)
            return (remaining, total, remaining / total)
        }

        let balance = max(llmState.creditsInfo?.balance ?? 0, 0)
        let total = max(balance, 1)
        return (balance, total, balance > 0 ? 1 : 0)
    }

    private var dailyCreditUsage: [DailyCreditUsage] {
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

    private func usageTint(for fractionRemaining: Double) -> Color {
        switch fractionRemaining {
            case 0..<0.2:
                return .red
            case 0.2..<0.5:
                return .orange
            default:
                return .accentColor
        }
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
                            Text("Loading full activity…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = allTransactionLoadError {
                        Text("Couldn't load full activity: \(error.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if fileActivityGroups.isEmpty {
                        Text("No file-linked credit usage in activity.")
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

    private var transactionCountLabel: some View {
        Text("\(transactions.count) of \(totalTransactionCount) loaded")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var activityCountLabel: some View {
        switch activityGrouping {
            case .recent:
                transactionCountLabel
            case .file:
                Text("\(fileActivityGroups.count) \(fileActivityGroups.count == 1 ? "file" : "files")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func transactionRow(
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
                    Label(fileLabel, systemImage: "doc.text")
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
    private func fileActivityRow(_ group: FileActivityGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: group.hasFileContext ? "doc.text" : "questionmark.folder")
                .font(.body)
                .foregroundStyle(group.hasFileContext ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.fileLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(group.transactions.count) AI \(group.transactions.count == 1 ? "request" : "requests")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(formatCredits(group.consumedCredits)) credits")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func transactionTitle(_ tx: CreditsTransaction) -> String {
        if tx.type == .consume { return "AI usage" }
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

    private func transactionSubtitle(_ tx: CreditsTransaction) -> String {
        let timestamp = tx.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard tx.type == .consume,
              let tier = transactionModelTier(tx)
        else {
            return timestamp
        }
        return "\(timestamp) · \(tier)"
    }

    private func transactionModelTier(_ tx: CreditsTransaction) -> String? {
        let modelKeys = [
            "model",
            "modelName",
            "model_name",
            "llmModel",
            "llm_model"
        ]

        for key in modelKeys {
            let value: String? = tx.getMetadataValue(key: key)
            guard let value, !value.isEmpty else { continue }
            let model = SupportedModel(rawValue: value)
            if model.rawValue == value {
                return model.excalidrawTierName
            }

            let lowered = value.lowercased()
            if lowered.contains("opus") {
                return "Extra High"
            }
            if lowered.contains("sonnet") {
                return "High"
            }
            if lowered.contains("haiku") {
                return "Medium"
            }
            if lowered.contains("mini") {
                return "Low"
            }
        }

        return nil
    }

    private var fileActivityGroups: [FileActivityGroup] {
        let grouped = Dictionary(grouping: allTransactions.filter { $0.amount < 0 }) { transaction in
            transactionFileLabel(transaction) ?? "Unknown File"
        }

        return grouped.map { fileLabel, transactions in
            FileActivityGroup(
                fileLabel: fileLabel,
                transactions: transactions.sorted { $0.createdAt > $1.createdAt },
                hasFileContext: fileLabel != "Unknown File"
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasFileContext != rhs.hasFileContext {
                return lhs.hasFileContext
            }
            if lhs.consumedCredits != rhs.consumedCredits {
                return lhs.consumedCredits > rhs.consumedCredits
            }
            return lhs.fileLabel.localizedCaseInsensitiveCompare(rhs.fileLabel) == .orderedAscending
        }
    }

    private func transactionFileLabel(_ tx: CreditsTransaction) -> String? {
        let nameKeys = [
            "fileName",
            "file_name",
            "filename",
            "fileTitle",
            "file_title",
            "documentName",
            "document_name",
            "canvasName",
            "canvas_name",
            "excalidrawFileName",
            "metadata.fileName",
            "metadata.file_name",
            "metadata.excalidrawFileName"
        ]

        for key in nameKeys {
            let value: String? = tx.getMetadataValue(key: key)
            if let value, !value.isEmpty {
                return value
            }
        }

        let pathKeys = [
            "filePath",
            "file_path",
            "fileURL",
            "file_url",
            "path",
            "url",
            "metadata.fileURL",
            "metadata.file_url",
            "metadata.path"
        ]

        for key in pathKeys {
            let value: String? = tx.getMetadataValue(key: key)
            if let value, !value.isEmpty {
                return lastPathComponent(from: value)
            }
        }

        let idKeys = [
            "fileID",
            "fileId",
            "file_id",
            "documentID",
            "documentId",
            "document_id",
            "metadata.fileID",
            "metadata.fileId",
            "metadata.file_id"
        ]

        for key in idKeys {
            let value: String? = tx.getMetadataValue(key: key)
            if let value, !value.isEmpty {
                return "File \(value.prefix(8))"
            }
        }

        return nil
    }

    private func lastPathComponent(from value: String) -> String {
        if let url = URL(string: value), url.scheme != nil {
            let component = url.lastPathComponent
            return component.isEmpty ? value : component
        }

        let component = URL(fileURLWithPath: value).lastPathComponent
        return component.isEmpty ? value : component
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
    private func loadAllTransactionsIfNeeded() async {
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
            debugLogTransactionMetadata(history.transactions, source: "page-\(page)")
        } catch {
            transactionLoadError = error
        }
    }

    private func debugLogTransactionMetadata(
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

    private func debugMetadataDescription(for tx: CreditsTransaction) -> String {
        #if DEBUG
        let directMetadata = tx.metadata?.description ?? "<nil>"
        let probeKeys = [
            "model",
            "modelName",
            "model_name",
            "llmModel",
            "llm_model",
            "fileName",
            "file_name",
            "filename",
            "fileTitle",
            "file_title",
            "documentName",
            "document_name",
            "canvasName",
            "canvas_name",
            "excalidrawFileName",
            "filePath",
            "file_path",
            "fileURL",
            "file_url",
            "path",
            "url",
            "fileID",
            "fileId",
            "file_id",
            "documentID",
            "documentId",
            "document_id",
            "metadata.fileName",
            "metadata.file_name",
            "metadata.excalidrawFileName",
            "metadata.fileURL",
            "metadata.file_url",
            "metadata.path",
            "metadata.fileID",
            "metadata.fileId",
            "metadata.file_id"
        ]

        let values = probeKeys.compactMap { key -> String? in
            let value: String? = tx.getMetadataValue(key: key)
            guard let value, !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }

        if values.isEmpty {
            return directMetadata
        }
        return "\(directMetadata) | probed: \(values.joined(separator: ", "))"
        #else
        return ""
        #endif
    }
}

//private struct AISettingsTabButton: View {
//    let title: String
//    let isSelected: Bool
//    let width: CGFloat
//    let height: CGFloat
//
//    var body: some View {
//        ZStack {
//            Text(title)
//                .font(.caption.weight(.semibold))
//        }
//        .frame(width: width, height: height)
//        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
//        .background {
//            Capsule()
//                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
//        }
//        .contentShape(Capsule())
//    }
//}

private struct SemiCircularUsageGauge: View {
    let fraction: Double
    let percentageText: String
    let detailText: String

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SemiCircleShape()
                .stroke(
                    Color.secondary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            SemiCircleShape(progress: clampedFraction)
                .stroke(
                    AIAppearancePalette.foregroundGradient,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )

            VStack(alignment: .center, spacing: 2) {
                Text(percentageText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(AIAppearancePalette.foregroundGradient)
                    .monospacedDigit()
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI credits remaining")
        .accessibilityValue("\(percentageText), \(detailText)")
    }
}

private struct SemiCircleShape: Shape {
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * clampedProgress),
            clockwise: false
        )
        return path
    }
}

private struct AISettingsGlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    @MainActor @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                }
        }
    }
}

private struct AISettingsGlassCapsuleModifier: ViewModifier {
    let tint: Color
    let isInteractive: Bool
    let isProminent: Bool

    @MainActor @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            let glass = isProminent
                ? Glass.regular.tint(tint.opacity(0.22))
                : Glass.clear.tint(tint.opacity(0.08))
            if isInteractive {
                content.glassEffect(glass.interactive(), in: Capsule())
            } else {
                content.glassEffect(glass, in: Capsule())
            }
        } else {
            content
                .background {
                    Capsule()
                        .fill(tint.opacity(isProminent ? 0.16 : 0.08))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(isProminent ? 0.26 : 0.0))
                }
        }
    }
}

private extension View {
    func aiSettingsGlassChip(cornerRadius: CGFloat) -> some View {
        modifier(AISettingsGlassChipModifier(cornerRadius: cornerRadius))
    }

    func aiSettingsGlassCapsule(
        tint: Color,
        isInteractive: Bool,
        isProminent: Bool = true
    ) -> some View {
        modifier(
            AISettingsGlassCapsuleModifier(
                tint: tint,
                isInteractive: isInteractive,
                isProminent: isProminent
            )
        )
    }
}
