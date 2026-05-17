//
//  ChatTopDownRevealTransition.swift
//  ExcalidrawZ
//
//  Shared top-down reveal transition for committed chat rows.
//

import SwiftUI

private struct ChatTopDownRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat = 0
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func body(content: Content) -> some View {
        let clamped = max(0, min(1, progress))
        
        content
            .opacity(clamped)
            .offset(y: (1 - clamped) * -14)
            .mask(alignment: .top) {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: proxy.size.height * clamped)
                        Spacer(minLength: 0)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color.white.opacity(0.52),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: min(28, proxy.size.height * max(clamped, 0.01)))
                        .offset(y: max(0, proxy.size.height * clamped - 28))
                        .opacity(clamped == 0 ? 0 : 1)
                    }
                }
            }
    }
}

private struct ChatRevealMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatTopDownRevealFrameModifier: ViewModifier, Animatable {
    var progress: CGFloat = 0
    @State private var measuredHeight: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let clamped = max(0, min(1, progress))
        let targetHeight = measuredHeight > 0 ? measuredHeight : nil

        if clamped >= 0.999 {
            content
        } else {
            ZStack(alignment: .top) {
                content
                    .chatTopDownReveal(progress: clamped)

                content
                    .hidden()
                    .allowsHitTesting(false)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ChatRevealMeasuredHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
            }
            .onPreferenceChange(ChatRevealMeasuredHeightKey.self) { height in
                guard height > 0 else { return }
                measuredHeight = height
            }
            .frame(height: targetHeight, alignment: .top)
            .clipped()
        }
    }
}

extension View {
    func chatTopDownReveal(progress: CGFloat) -> some View {
        modifier(ChatTopDownRevealModifier(progress: progress))
    }

    func chatTopDownRevealFrame(progress: CGFloat) -> some View {
        modifier(ChatTopDownRevealFrameModifier(progress: progress))
    }
}

extension AnyTransition {
    static var chatTopDownReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ChatTopDownRevealModifier(progress: 0),
                identity: ChatTopDownRevealModifier(progress: 1)
            ),
            removal: .opacity
        )
    }
}
