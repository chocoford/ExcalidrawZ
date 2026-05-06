//
//  LowCreditsBanner.swift
//  ExcalidrawZ
//
//  Self-gated "credits running low" banner. Reads
//  `LLMStateObject.creditsInfo` from the environment and renders the warning
//  card only while `balance < threshold`; otherwise it's a no-op (renders
//  nothing). Visibility is owned by this view so callers can drop it into
//  any layout — typically a `VStack(spacing: -peekBottom)` above an
//  opaque-backed sibling — without re-implementing the threshold check.
//
//  The peek-out effect (banner's bottom tucked behind the next sibling)
//  needs the caller to:
//   - parent the banner in a `VStack` with negative spacing (≈ `peekBottom`)
//   - put an opaque-backed sibling immediately below (input box, card, etc.)
//   - pass the same magnitude as `peekBottom` here so the orange extends
//     past the visible edge by exactly that much.
//

import SwiftUI
import SFSafeSymbols
import LLMKit
import LLMCore

struct LowCreditsBannerView: View {
    @EnvironmentObject private var llmState: LLMStateObject

    /// Show only while `creditsInfo.balance < threshold`. Default 100 — at
    /// that point the user has a few exchanges of runway, enough time to
    /// react to the hint before hitting `LLMError.insufficientCredits`.
    var threshold: Double = 100

    /// Extra space added below the content *inside* the orange background.
    /// Set to a positive value when the caller stacks the banner above a
    /// sibling with a negative `VStack` spacing, so the orange extends
    /// behind the sibling and the rounded bottom edge stays hidden.
    /// Default 0 → clean self-contained card.
    var peekBottom: CGFloat = 0
    
    public init(threshold: Double = 100, peekBottom: CGFloat = 0) {
        self.threshold = threshold
        self.peekBottom = peekBottom
    }

    private var balance: Double? {
        llmState.creditsInfo?.balance
    }

    private var shouldShow: Bool {
        guard let balance else { return false }
        return balance < threshold
    }

    var body: some View {
        ZStack {
            if shouldShow, let balance {
                bannerCard(balance: balance)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShow)
    }

    @ViewBuilder
    private func bannerCard(balance: Double) -> some View {
        Button {
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
        } label: {
            HStack(spacing: 6) {
                Image(systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.orange)
                Text("Only \(Int(balance)) credits left — tap to top up")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemSymbol: .arrowRight)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            // Adds *on top of* the 6pt bottom from `.padding(.vertical, 6)`,
            // so total bottom inset = 6 + peekBottom. The orange background
            // is applied after this, so it grows with the padding.
            .padding(.bottom, peekBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.orange.opacity(0.15))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("standalone") {
    LowCreditsBannerView()
        .padding()
        .frame(width: 320)
}

#Preview("peek behind input") {
    VStack(spacing: -18) {
        LowCreditsBannerView(peekBottom: 18)
        RoundedRectangle(cornerRadius: 20)
            .fill(.regularMaterial)
            .frame(height: 60)
    }
    .padding()
    .frame(width: 320)
}
#endif
