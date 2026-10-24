import Foundation
import Combine
import LLMKit
import LLMCore

/// In-memory discovery metadata for the selected connection. Credentials never enter the cache.
@MainActor
final class AIInferenceModelCatalog: ObservableObject {
    static let shared = AIInferenceModelCatalog()

    struct Snapshot {
        var revision = -1
        var models: [LLMBYOKModel] = []
        var isLoading = false
        var errorMessage: String?
    }

    @Published private(set) var snapshot = Snapshot()
    private var request: Task<Void, Never>?
    private var requestID = UUID()
    private var didLoad = false
    private let fetch: @Sendable (LLMBYOKProvider) async throws -> [LLMBYOKModel]

    init(fetch: @escaping @Sendable (LLMBYOKProvider) async throws -> [LLMBYOKModel] = {
        try await LLMClient.shared.listBYOKModels(provider: $0)
    }) {
        self.fetch = fetch
    }

    func snapshot(for billing: AIInferenceBillingState) -> Snapshot {
        snapshot.revision == billing.modelCatalogRevision ? snapshot : Snapshot()
    }

    func displayName(for id: String, billing: AIInferenceBillingState) -> String {
        snapshot(for: billing).models.first(where: { $0.id == id })?.displayName ?? id
    }

    func cancel() {
        request?.cancel()
        request = nil
        requestID = UUID()
        snapshot.isLoading = false
    }

    func load(for billing: AIInferenceBillingState, force: Bool = false) async {
        let revision = billing.modelCatalogRevision
        if snapshot.revision == revision, !force {
            if let request { await request.value; return }
            if didLoad { return }
        }
        cancel()
        let id = UUID()
        requestID = id
        didLoad = false
        let cachedModels = snapshot.revision == revision ? snapshot.models : []
        snapshot = Snapshot(revision: revision)
        guard billing.usesBYOK, billing.hasStoredKey else { return }
        snapshot.models = cachedModels
        if let configuration = billing.configuration, configuration.modelDiscovery == nil {
            didLoad = true
            return
        }

        let provider: LLMBYOKProvider
        do {
            provider = try billing.modelDiscoveryProvider()
        } catch {
            snapshot.errorMessage = message(for: error)
            didLoad = true
            return
        }

        snapshot.isLoading = true
        let fetch = fetch
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if requestID == id {
                    snapshot.isLoading = false
                    request = nil
                }
            }
            do {
                // Coalesce automatic refreshes while connection settings are being edited.
                if !force { try await Task.sleep(nanoseconds: 300_000_000) }
                let models = try await fetch(provider)
                try Task.checkCancellation()
                guard requestID == id, billing.modelCatalogRevision == revision, billing.usesBYOK else { return }
                var seen = Set<String>()
                snapshot.models = models.filter { seen.insert($0.id).inserted }.sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                didLoad = true
            } catch is CancellationError {
            } catch {
                guard requestID == id, billing.modelCatalogRevision == revision, billing.usesBYOK else { return }
                snapshot.errorMessage = message(for: error)
                didLoad = true
            }
        }
        request = operation
        await operation.value
    }

    private func message(for error: Error) -> String {
        AIInferenceErrorMessage.localizedError(for: error)?.localizedDescription
            ?? String(localizable: .aiBYOKModelListFailed)
    }
}
