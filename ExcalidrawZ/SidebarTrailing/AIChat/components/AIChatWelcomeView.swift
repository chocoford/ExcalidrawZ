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
    /// Caller dismisses by flipping its own state — we just notify.
    var onGetStarted: () -> Void
    
    @State private var isHeroIconPresented = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            hero
                .padding(.bottom, 24)

            featureList
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            
            Spacer(minLength: 12)
            
            getStartedButton
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.smooth) {
                isHeroIconPresented = true
            }
        }
    }
    
    // MARK: - Hero
    
    @ViewBuilder
    private var hero: some View {
        VStack(spacing: 14) {
            heroIcon
            
            VStack(spacing: 6) {
                Text("Welcome to AI Chat")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                
                Text("Your hands-on assistant for the canvas — ask questions, edit elements, and let it drive your drawings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    @ViewBuilder
    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.35),
                            Color.purple.opacity(0.25),
                            Color.pink.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)
                .blur(radius: 18)
            
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                
                Image(systemSymbol: .sparkles)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 64, height: 64)
        }
    }
    
    // MARK: - Feature list
    
    @ViewBuilder
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureRow(
                icon: .pencilTipCropCircle,
                tint: .accentColor,
                title: "Edit your canvas",
                subtitle: "Adjust elements, position shapes, or restyle existing drawings."
            )
            FeatureRow(
                icon: .photoOnRectangle,
                tint: .pink,
                title: "Read what you've drawn",
                subtitle: "Snapshot the canvas so the AI can reason about it visually."
            )
            FeatureRow(
                icon: .booksVertical,
                tint: .purple,
                title: "Browse files & libraries",
                subtitle: "Find prior work and pull in library items — with your permission."
            )
            FeatureRow(
                icon: .arrowUturnBackwardCircle,
                tint: .orange,
                title: "Revert any turn",
                subtitle: "Every AI edit is checkpointed — roll back instantly if you don't like it."
            )
        }
    }
    
    // MARK: - Get Started
    
    @ViewBuilder
    private var getStartedButton: some View {
        VStack(spacing: 8) {
            Button {
                onGetStarted()
            } label: {
                HStack(spacing: 6) {
                    Text("Get Started")
                        .fontWeight(.semibold)
                    Image(systemSymbol: .arrowRight)
                        .font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
            .keyboardShortcut(.defaultAction)
            
            Text("You can change AI settings any time from the More menu.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: SFSymbol
    let tint: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
    }
}

#if DEBUG
#Preview {
    AIChatWelcomeView(onGetStarted: {})
        .frame(width: 280, height: 600)
        .padding()
}
#endif
