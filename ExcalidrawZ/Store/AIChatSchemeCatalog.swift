import Observation
import Combine
import Foundation
import LLMCore
import LLMKit

@MainActor
@Observable
final class AIChatSchemeCatalog {
    static let shared = AIChatSchemeCatalog()
    static let schemeID = "excalidraw-canvas"

    private(set) var scheme: LLMSchemeDescriptor?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var authentication: AnyCancellable?

    var options: [ExcalidrawModelProfileOption] { scheme?.excalidrawModelOptions ?? [] }

    func observeAuthentication(in state: LLMStateObject) {
        authentication = state.$isAuthenticated.removeDuplicates().sink { [weak self] authenticated in
            Task { @MainActor in
                guard let self else { return }
                self.invalidate()
                if authenticated { await self.refresh() }
            }
        }
    }

    func invalidate() {
        generation += 1
        scheme = nil
        errorMessage = nil
        isLoading = false
    }

    func refresh(force: Bool = false, forServerConversation: Bool = false) async {
        guard AIChatAvailability.supportsManagedInference, AIChatAvailability.canUseAI else { return }
        guard !AIChatAvailability.usesDirectInference || forServerConversation else { return }
        guard force || (scheme == nil && !isLoading) else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let value = try await LLMClient.shared.getScheme(id: Self.schemeID)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            scheme = value
            errorMessage = nil
        } catch {
            guard generation == requestGeneration else { return }
            scheme = nil
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func requireProfile(_ id: String) throws -> ExcalidrawModelProfileOption {
        if let errorMessage { throw AIChatRoutingError.catalog(errorMessage) }
        guard let profile = scheme?.profiles.first(where: { $0.id == id }),
              profile.access?.allowed != false else {
            throw AIChatRoutingError.profileUnavailable(id)
        }
        return ExcalidrawModelProfileOption(profile: profile)
    }
}
