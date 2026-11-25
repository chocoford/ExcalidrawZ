import Observation
import Foundation
import LLMKit
import LLMCore

/// In-memory discovery metadata for the selected connection. Credentials never enter the cache.
@MainActor
@Observable
final class AIInferenceModelCatalog {
    static let shared = AIInferenceModelCatalog()

    struct Snapshot {
        var revision = -1
        var profileID: String?
        var integrationMode: AIInferenceIntegrationMode = .optimized
        var models: [LLMBYOKModel] = []
        var isLoading = false
        var errorMessage: String?
    }

    private(set) var snapshot = Snapshot()
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var didLoad = false
    private let fetch: @Sendable (LLMBYOKProvider, AIInferenceIntegrationMode) async throws -> [LLMBYOKModel]

    init(fetch: @escaping @Sendable (LLMBYOKProvider, AIInferenceIntegrationMode) async throws -> [LLMBYOKModel] = {
        if $1 == .basic { return try await LLMClient(directBYOK: $0).listBYOKModels() }
        return try await LLMClient.shared.listBYOKModels(provider: $0)
    }) {
        self.fetch = fetch
    }

    func snapshot(for billing: AIInferenceBillingState, profileID: String? = nil, integrationMode: AIInferenceIntegrationMode? = nil) -> Snapshot {
        snapshot.revision == billing.modelCatalogRevision && snapshot.profileID == (profileID ?? billing.selectedProfileID)
            && snapshot.integrationMode == (integrationMode ?? billing.integrationMode)
            ? snapshot : Snapshot()
    }

    func displayName(for id: String, billing: AIInferenceBillingState, profileID: String? = nil, integrationMode: AIInferenceIntegrationMode? = nil) -> String {
        snapshot(for: billing, profileID: profileID, integrationMode: integrationMode).models.first(where: { $0.id == id })?.displayName ?? id
    }

    func cancel() {
        request?.cancel()
        request = nil
        requestID = UUID()
        snapshot.isLoading = false
    }

    func load(for billing: AIInferenceBillingState, profileID: String? = nil, integrationMode: AIInferenceIntegrationMode? = nil, force: Bool = false) async {
        let revision = billing.modelCatalogRevision
        let connectionID = profileID ?? billing.selectedProfileID
        let mode = integrationMode ?? billing.integrationMode
        let sameConnection = snapshot.profileID == connectionID && snapshot.integrationMode == mode
        if snapshot.revision == revision, sameConnection, !force {
            if let request { await request.value; return }
            if didLoad { return }
        }
        cancel()
        let id = UUID()
        requestID = id
        didLoad = false
        let cachedModels = snapshot.revision == revision && sameConnection ? snapshot.models : []
        snapshot = Snapshot(revision: revision, profileID: connectionID, integrationMode: mode)
        guard profileID != nil || (billing.usesBYOK && billing.hasStoredKey) else { return }
        snapshot.models = cachedModels
        if let configuration = billing.profiles.first(where: { $0.id == connectionID })?.configuration,
           configuration.modelDiscovery == nil {
            didLoad = true
            return
        }

        let provider: LLMBYOKProvider
        do {
            provider = try billing.modelDiscoveryProvider(profileID: profileID)
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
                let models = try await fetch(provider, mode)
                try Task.checkCancellation()
                guard requestID == id, billing.modelCatalogRevision == revision, (profileID != nil || billing.usesBYOK) else { return }
                var seen = Set<String>()
                snapshot.models = models.filter { seen.insert($0.id).inserted }.sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                didLoad = true
            } catch is CancellationError {
            } catch {
                guard requestID == id, billing.modelCatalogRevision == revision, (profileID != nil || billing.usesBYOK) else { return }
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
