//
//  AIChatWelcomeView.swift
//  ExcalidrawZ
//
//  First-run cover for the AI chat inspector. Shown when the user has
//  never started a conversation; the host (`AIChatView`) checks
//  `llmState.conversations` and switches to the regular chat surface
//  once the user taps Get Started or as soon as a conversation exists.
//

import SwiftUI
import SFSafeSymbols

struct AIChatWelcomeView: View {
    private let animationRate: Double = 1.5
    
    /// Caller dismisses by flipping its own state — we just notify.
    var onGetStarted: () -> Void
    private let buttonTitle: String
    private let buttonCaption: String
    private let buttonURL: URL?
    private let requiresEnableConfirmation: Bool
    
    @State private var hasAnimatedIn = false
    @State private var isBackgroundPresented = false
    @State private var isHeroIconPresented = false
    @State private var isHeroTextPresented = false
    @State private var isGetStartedPresented = false
    @State private var isFeatureListPresented = false
    
    
    @State private var isDismissing = false
    @State private var isConfirmingEnable = false

    init(
        buttonTitle: String = String(localizable: .aiChatWelcomeButtonGetStarted),
        buttonCaption: String = String(localizable: .aiChatWelcomeGetStartedCaption),
        buttonURL: URL? = nil,
        requiresEnableConfirmation: Bool = false,
        onGetStarted: @escaping () -> Void
    ) {
        self.buttonTitle = buttonTitle
        self.buttonCaption = buttonCaption
        self.buttonURL = buttonURL
        self.requiresEnableConfirmation = requiresEnableConfirmation
        self.onGetStarted = onGetStarted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            
            hero
                .padding(.bottom, 18)
            
            breakpoint
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            
            getStartedButton
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            
            featureList
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            
            Spacer(minLength: 16)
        }
        .allowsHitTesting(!isDismissing)
        .background {
            animatedBackground
                .ignoresSafeArea()
        }
        .task {
            guard !hasAnimatedIn else { return }
            hasAnimatedIn = true
            
            withAnimation(.easeOut(duration: scaled(0.9))) {
                isBackgroundPresented = true
            }
            
            try? await Task.sleep(for: milliseconds(120))
            withAnimation(.spring(response: scaled(0.72), dampingFraction: 0.78)) {
                isHeroIconPresented = true
            }
            
            try? await Task.sleep(for: milliseconds(180))
            withAnimation(.smooth(duration: scaled(0.55))) {
                isHeroTextPresented = true
            }
            
            try? await Task.sleep(for: milliseconds(140))
            withAnimation(.spring(response: scaled(0.5), dampingFraction: 0.88)) {
                isGetStartedPresented = true
            }
            
            try? await Task.sleep(for: milliseconds(110))
            withAnimation(.smooth(duration: scaled(0.55))) {
                isFeatureListPresented = true
            }
        }
        .sheet(isPresented: $isConfirmingEnable) {
            AIEnableConsentSheet {
                Task {
                    await dismissAndStart()
                }
            }
        }
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var animatedBackground: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let topDrift = CGFloat(sin(time * 0.42)) * 18
            let bottomDrift = CGFloat(cos(time * 0.37)) * 20
            let orbit = CGFloat(sin(time * 0.28)) * 26
            let topHueA = 0.56 + sin(time * 0.12) * 0.035
            let topHueB = 0.64 + cos(time * 0.16) * 0.03
            let bottomHueA = 0.9 + sin(time * 0.14) * 0.025
            let bottomHueB = 0.78 + cos(time * 0.11) * 0.035
            
            GeometryReader { proxy in
                ZStack {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color(hue: topHueA, saturation: 0.62, brightness: 0.98).opacity(0.28),
                                Color(hue: topHueB, saturation: 0.48, brightness: 0.96).opacity(0.14),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: proxy.size.height * 0.4)
                        .blur(radius: 26)
                        .offset(x: 0, y: (isBackgroundPresented ? -12 : -140) + topDrift)
                        .opacity(isBackgroundPresented ? 1 : 0)
                        
                        Spacer()
                        
                        LinearGradient(
                            colors: [
                                .clear,
                                Color(hue: bottomHueB, saturation: 0.5, brightness: 0.92).opacity(0.14),
                                Color(hue: bottomHueA, saturation: 0.56, brightness: 0.94).opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: proxy.size.height * 0.44)
                        .blur(radius: 28)
                        .offset(x: 0, y: (isBackgroundPresented ? 14 : 170) + bottomDrift)
                        .opacity(isBackgroundPresented ? 1 : 0)
                    }
                    
                    Circle()
                        .fill(Color(hue: topHueA, saturation: 0.62, brightness: 1).opacity(0.1))
                        .frame(width: 220, height: 220)
                        .blur(radius: 48)
                        .offset(x: orbit * 0.8, y: -90 + topDrift * 0.35)
                        .opacity(isBackgroundPresented ? (isDismissing ? 0.24 : 1) : 0)
                    
                    Circle()
                        .fill(Color(hue: bottomHueA, saturation: 0.58, brightness: 0.98).opacity(0.08))
                        .frame(width: 240, height: 240)
                        .blur(radius: 54)
                        .offset(x: -orbit * 0.9, y: 190 + bottomDrift * 0.35)
                        .opacity(isBackgroundPresented ? (isDismissing ? 0.18 : 0.95) : 0)
                }
                .overlay {
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color(hue: topHueA, saturation: 0.5, brightness: 1).opacity(0.06),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: 260
                    )
                    .offset(x: 0, y: -24)
                    .opacity(isBackgroundPresented ? (isDismissing ? 0.14 : 1) : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
        .opacity(isDismissing ? 0.7 : 1)
    }
    
    // MARK: - Hero
    
    @ViewBuilder
    private var hero: some View {
        VStack(spacing: 14) {
            heroIcon
            
            VStack(spacing: 6) {
                Text(localizable: .aiChatWelcomeCaption)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                
                Text(localizable: .aiChatWelcomeTitle)
                    .font(.title2.weight(.semibold))
                    .tracking(-0.3)
                    .multilineTextAlignment(.center)
                
                Text(localizable: .aiChatWelcomeMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .offset(y: isHeroTextPresented ? 0 : 16)
            .opacity(isHeroTextPresented ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .blur(radius: isDismissing ? 2 : 0)
    }
    
    @ViewBuilder
    private var heroIcon: some View {
        AIIdentityIcon(size: 64)
        .rotation3DEffect(
            .degrees(heroIconRotation),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center
        )
        .scaleEffect(heroIconScale)
        .opacity(heroIconOpacity)
    }
    
    @ViewBuilder
    private var breakpoint: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.secondary.opacity(0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            Image(systemSymbol: .sparkles)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(8)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .offset(y: breakpointOffset)
        .opacity(breakpointOpacity)
        .blur(radius: isDismissing ? 2 : 0)
    }
    
    // MARK: - Feature list
    
    @ViewBuilder
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureRow(
                icon: .pencilTipCropCircle,
                tint: .accentColor,
                title: String(localizable: .aiChatWelcomeFeatureDrawTitle),
                subtitle: String(localizable: .aiChatWelcomeFeatureDrawSubtitle)
            )
            FeatureRow(
                icon: .photoOnRectangle,
                tint: .pink,
                title: String(localizable: .aiChatWelcomeFeatureReadTitle),
                subtitle: String(localizable: .aiChatWelcomeFeatureReadSubtitle),
            )
            FeatureRow(
                icon: .booksVertical,
                tint: .purple,
                title: String(localizable: .aiChatWelcomeFeatureBrowseTitle),
                subtitle: String(localizable: .aiChatWelcomeFeatureBrowseSubtitle)
            )
            FeatureRow(
                icon: .arrowUturnBackwardCircle,
                tint: .orange,
                title: String(localizable: .aiChatWelcomeFeatureRevertTitle),
                subtitle: String(localizable: .aiChatWelcomeFeatureRevertSubtitle)
            )
        }
        .offset(y: featureListOffset)
        .opacity(featureListOpacity)
        .blur(radius: isDismissing ? 4 : 0)
    }
    
    // MARK: - Get Started
    
    @ViewBuilder
    private var getStartedButton: some View {
        VStack(spacing: 8) {
            if let buttonURL {
                Link(destination: buttonURL) {
                    getStartedButtonLabel
                }
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .modern)
                .keyboardShortcut(.defaultAction)
                .disabled(isDismissing)
            } else {
                Button {
                    if requiresEnableConfirmation {
                        isConfirmingEnable = true
                    } else {
                        Task {
                            await dismissAndStart()
                        }
                    }
                } label: {
                    getStartedButtonLabel
                }
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .modern)
                .keyboardShortcut(.defaultAction)
                .disabled(isDismissing)
            }
            
            getStartedCaption
        }
        .offset(y: ctaOffset)
        .opacity(ctaOpacity)
        .blur(radius: isDismissing ? 4 : 0)
    }

    @ViewBuilder
    private var getStartedCaption: some View {
        if buttonURL != nil {
            Text(buttonCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                        }
                }
        } else {
            Text(buttonCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var getStartedButtonLabel: some View {
        HStack(spacing: 6) {
            Text(buttonTitle)
                .fontWeight(.semibold)
            Image(systemSymbol: .arrowRight)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var featureListBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.textBackgroundColor.opacity(0.8))
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                }
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
            }
        }
    }
    
    private var heroIconOffset: CGFloat {
        if isDismissing { return -24 }
        return isHeroIconPresented ? 0 : 44
    }
    
    private var heroIconScale: CGFloat {
        if isDismissing { return 0.72 }
        return isHeroIconPresented ? 1 : 0.82
    }
    
    private var heroIconOpacity: Double {
        if isDismissing { return 0 }
        return isHeroIconPresented ? 1 : 0
    }
    
    private var heroIconRotation: Double {
        if isDismissing { return 56 }
        return isHeroIconPresented ? 0 : -90
    }
    
    private var breakpointOffset: CGFloat {
        if isDismissing { return -8 }
        return isHeroTextPresented ? 0 : 12
    }
    
    private var breakpointOpacity: Double {
        if isDismissing { return 0 }
        return isHeroTextPresented ? 1 : 0
    }
    
    private var featureListOffset: CGFloat {
        if isDismissing { return 18 }
        return isFeatureListPresented ? 0 : 20
    }
    
    private var featureListOpacity: Double {
        if isDismissing { return 0 }
        return isFeatureListPresented ? 1 : 0
    }
    
    private var ctaOffset: CGFloat {
        if isDismissing { return -10 }
        return isGetStartedPresented ? 0 : 18
    }
    
    private var ctaOpacity: Double {
        if isDismissing { return 0 }
        return isGetStartedPresented ? 1 : 0
    }
    
    @MainActor
    private func dismissAndStart() async {
        guard !isDismissing else { return }
        withAnimation(.smooth) {
            isDismissing = true
        }
        
        withAnimation(.smooth(duration: scaled(0.18))) {
            isFeatureListPresented = false
        }
        
        try? await Task.sleep(for: milliseconds(90))
        withAnimation(.smooth(duration: scaled(0.2))) {
            isGetStartedPresented = false
        }
        
        try? await Task.sleep(for: milliseconds(90))
        withAnimation(.smooth(duration: scaled(0.2))) {
            isHeroTextPresented = false
        }
        
        try? await Task.sleep(for: milliseconds(90))
        withAnimation(.spring(response: scaled(0.34), dampingFraction: 0.84)) {
            isHeroIconPresented = false
        }
        
        try? await Task.sleep(for: milliseconds(140))
        withAnimation(.easeOut(duration: scaled(0.28))) {
            isBackgroundPresented = false
        }
        
        try? await Task.sleep(for: milliseconds(180))
        onGetStarted()
    }
    
    private func scaled(_ duration: Double) -> Double {
        duration * animationRate
    }
    
    private func milliseconds(_ value: Double) -> Duration {
        .milliseconds(value * animationRate)
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: SFSymbol
    let tint: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemSymbol: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: Capsule())
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.48),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            } else {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .stroke(.separator, lineWidth: 0.5)
                }
            }
        }
        .padding(1)
    }
}

#if DEBUG
#Preview {
    AIChatWelcomeView(onGetStarted: {})
        .frame(width: 280, height: 600)
        .padding()
}
#endif
