//
//  AIChatErrorPresenter.swift
//  ExcalidrawZ
//
//  Maps `LLMError` cases to user-facing UX. The backend distinguishes a few
//  intent-bearing failures (insufficient credits, unauthorized, rate-limited,
//  forbidden) that deserve dedicated copy — and eventually dedicated entry
//  points (paywall sheet, sign-in sheet). Known BYOK failures are localized
//  separately so provider credits are not confused with app credits.
//

import SwiftUI
import SwiftyAlert
import LLMKit

extension AlertToastAction {
    /// Surface a chat-flow error to the user.
    ///
    /// - `CancellationError` is swallowed (user-initiated stop is not an error).
    /// - Predefined `LLMError` cases get hand-written copy here. The server
    ///   `message` payload is intentionally *not* surfaced for those — copy is
    ///   driven by intent, not server phrasing. (TODO: route credits /
    ///   unauthorized to dedicated sheets once entry points land.)
    /// - `.forbidden(reason:)` does pass `reason` through when present, since
    ///   403 covers several distinct policy gates that a short reason
    ///   meaningfully clarifies.
    /// - Known BYOK errors use app-localized copy before platform error handling.
    /// - Other errors defer to their `LocalizedError.errorDescription`.
    @MainActor
    func presentAIChatError(_ error: Error) {
        if error is CancellationError { return }

        if let error = AIInferenceErrorMessage.localizedError(for: error) {
            self(error)
            return
        }

        guard let llmError = error as? LLMError else {
            self(error)
            return
        }

        switch llmError {
            case .insufficientCredits:
                // Open the paywall directly — credits are an actionable, money-
                // based wall, so a toast that just says "top up" would just be a
                // dead end. `Store.shared.togglePaywall` flips the global paywall
                // sheet, which is already mounted by `PaywallModifier` on the
                // root content view.
                Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            case .unauthorized:
                // TODO: open sign-in sheet once an entry point lands.
                self(AIChatToastMessage(String(localizable: .aiChatErrorUnauthorization)))
            case .forbidden(let reason):
                self(AIChatToastMessage(reason ?? String(localizable: .aiChatErrorForbiddenFallback)))
            case .rateLimited:
                self(AIChatToastMessage(String(localizable: .aiChatErrorRateLimited)))
            case .accessDenied, .server, .decoding, .network:
                // The SDK supplies the fallback description for unrecognized errors.
                self(llmError)
        }
    }
}

/// Tiny `LocalizedError` wrapper so we can hand the existing `alertToast(_:)`
/// channel a custom-titled error without depending on the AlertToast type
/// directly. `errorDescription` is what SwiftyAlert renders.
private struct AIChatToastMessage: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
