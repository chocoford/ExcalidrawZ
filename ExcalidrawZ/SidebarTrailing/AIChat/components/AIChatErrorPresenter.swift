//
//  AIChatErrorPresenter.swift
//  ExcalidrawZ
//
//  Maps `LLMError` cases to user-facing UX. The backend distinguishes a few
//  intent-bearing failures (insufficient credits, unauthorized, rate-limited,
//  forbidden) that deserve dedicated copy — and eventually dedicated entry
//  points (paywall sheet, sign-in sheet). Everything else falls through to a
//  generic toast so we never leak server-provided phrasing like "Tencent COS
//  STS not configured" to end users.
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
    /// - Other cases (`.server`, `.decoding`, `.network`) and any non-`LLMError`
    ///   throwable defer to `LocalizedError.errorDescription`, which we kept
    ///   generic in `LLMError` ("Server error (NNN).") to avoid leaking
    ///   internal text.
    @MainActor
    func presentAIChatError(_ error: Error) {
        if error is CancellationError { return }

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
            self(AIChatToastMessage("Please sign in to continue."))
        case .forbidden(let reason):
            self(AIChatToastMessage(reason ?? "Request was denied."))
        case .rateLimited:
            self(AIChatToastMessage("Too many requests. Please slow down."))
        case .server, .decoding, .network:
            // Defers to `LLMError.errorDescription` (generic by design — the
            // server's reason string is not exposed). The underlying error is
            // still logged via SwiftyAlert's internal logger.
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
