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
    enum Presentation {
        case banner
        case compactCapsule
    }

    static let defaultThreshold: Double = 50

    @EnvironmentObject private var llmState: LLMStateObject

    /// Show only while `creditsInfo.balance < threshold`. Default 50 — at
    /// that point the user has a few exchanges of runway, enough time to
    /// react to the hint before hitting `LLMError.insufficientCredits`.
    var threshold: Double = Self.defaultThreshold

    /// Extra space added below the content *inside* the orange background.
    /// Set to a positive value when the caller stacks the banner above a
    /// sibling with a negative `VStack` spacing, so the orange extends
    /// behind the sibling and the rounded bottom edge stays hidden.
    /// Default 0 → clean self-contained card.
    var peekBottom: CGFloat = 0

    var presentation: Presentation = .banner

    init(
        threshold: Double = Self.defaultThreshold,
        peekBottom: CGFloat = 0,
        presentation: Presentation = .banner
    ) {
        self.threshold = threshold
        self.peekBottom = peekBottom
        self.presentation = presentation
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
            if let balance, shouldShow {
                switch presentation {
                    case .banner:
                        bannerCard(balance: balance)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    case .compactCapsule:
                        compactCapsule(balance: balance)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShow)
    }

    @ViewBuilder
    private func bannerCard(balance: Double) -> some View {
        Button {
            Task { @MainActor in
                Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.orange)
                Text(localizable: .aiChatLowCreditsBannerLabel(balance.formatted(.number.precision(.fractionLength(2)))))
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
        }
        .tint(.orange)
        .modernButtonStyle(style: .glass, shape: .roundedRectangle(14))
    }

    @ViewBuilder
    private func compactCapsule(balance: Double) -> some View {
        Button {
            Task { @MainActor in
                Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemSymbol: .exclamationmarkTriangleFill)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(localizable: .aiChatButtonCreditsCount(formattedBalance(balance)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
    }

    private func formattedBalance(_ balance: Double) -> String {
        balance.formatted(.number.precision(.fractionLength(2)))
    }
}

struct AICreditsToolbarButton: View {
    @EnvironmentObject private var llmState: LLMStateObject

    private var action: (() -> Void)?

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                Task { @MainActor in
                    Store.shared.togglePaywall(reason: .manaully)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemSymbol: .sparkles)
                if let balance = llmState.creditsInfo?.balance, balance > 0 {
                    Text(balance.formatted(.number.precision(.fractionLength(2))))
                }
            }
            .foregroundStyle(AIAppearancePalette.foregroundGradient)
        }
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
