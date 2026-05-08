//
//  ChatScrollView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/01/10.
//

import SwiftUI

struct ScrollToBottomRequest: Equatable {
    var token: Int = 0
    var animated: Bool = false
}

enum ChatScrollAnimation {
    static let revealDuration: Double = 0.6
    static let scrollDuration: Double = 0.6
}

/// SwiftUI-native chat scroll view backed by `ScrollView` + `LazyVStack`.
///
/// "Pinned to bottom" is observed directly: a 1pt anchor at the bottom of the
/// lazy stack drives `isPinnedToBottom` via `.onAppear` / `.onDisappear` —
/// LazyVStack mounts the anchor when it's near the visible region and unmounts
/// it once it scrolls out of the prerender buffer. No content/viewport/offset
/// height tracking, no distance-to-bottom heuristics. This sidesteps a class
/// of bugs caused by SwiftUI's `.background` GeometryReader on `ScrollView`
/// reporting flaky sizes (NSScrollView's clipView vs documentView swap during
/// scroll on macOS).
///
/// During streaming we drive a low-frequency `proxy.scrollTo(anchor)` loop
/// gated on `isStreaming && isPinnedToBottom`, so the viewport keeps glued to
/// the bottom while content grows. A short tail extends the loop past the
/// stream's end to cover `SmoothStreamingText`'s reveal animation.
struct ChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    /// Streaming flag from the caller. While true (and the user hasn't scrolled
    /// off the bottom), the container runs an internal scroll-follow loop.
    private let isStreaming: Bool
    private let content: Content

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        isStreaming: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.isStreaming = isStreaming
        self.content = content()
    }

    var body: some View {
        ChatScrollContainer(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming
        ) {
            content
        }
    }
}

/// Per-row chrome (padding, etc). With the List-backed implementation we used
/// `listRowInsets`; now it's plain padding so every row controls its own gutters.
struct ChatScrollRow<Content: View>: View {
    private let content: Content


    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Container

private struct ChatScrollContainer<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let isStreaming: Bool
    private let content: Content

    private let bottomAnchorID = "chat-scroll-bottom-anchor"

    /// Extends the follow-loop a bit after `isStreaming` flips false, so the
    /// `SmoothStreamingText` reveal animation tail (~0.5 s) doesn't leave the
    /// viewport stuck above the freshly-grown content.
    @State private var followTail: Bool = false

    /// Asymmetric debounce for the anchor's mount-state → `isPinnedToBottom`:
    /// `onAppear` schedules a flip-to-true after a stable window; `onDisappear`
    /// cancels that schedule and flips false immediately. When the anchor sits
    /// right at LazyVStack's prerender edge it ping-pongs mount/unmount as
    /// content reflows, so naive event-to-binding wiring would have
    /// `isPinnedToBottom` chattering. Asymmetric handling biases ambiguity
    /// toward "unpinned" — which is what we want, since the user *isn't* at the
    /// bottom in that ambiguous middle zone.
    @State private var pinSettleTask: Task<Void, Never>?

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        isStreaming: Bool,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.isStreaming = isStreaming
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    content

                    Color.clear.frame(height: 20)

                    Color.clear
                        .frame(height: 20)
                        .id(bottomAnchorID)
                        .onAppear { handleAnchorAppear() }
                        .onDisappear { handleAnchorDisappear() }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: scrollToBottomRequest.token) { _ in
                scrollToBottom(proxy, animated: scrollToBottomRequest.animated)
            }
            .onChange(of: isStreaming) { nowStreaming in
                guard !nowStreaming else { return }
                followTail = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    followTail = false
                }
            }
            // ID gates on whether we *want to* follow at all (streaming or in
            // tail), not on `isPinnedToBottom`. Otherwise every anchor
            // mount/unmount on the prerender boundary would tear down the
            // task and start a new one — restart-storm hammering scrollTo
            // while layout is still in flight is the other half of the
            // crash. The pin check moves *inside* the loop so a flickering
            // pin just skips iterations cleanly.
            .task(id: isStreaming || followTail) {
                guard isStreaming || followTail else { return }
                while !Task.isCancelled {
                    if isPinnedToBottom {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
    }

    private func handleAnchorAppear() {
        pinSettleTask?.cancel()
        pinSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if !isPinnedToBottom {
                isPinnedToBottom = true
            }
        }
    }

    private func handleAnchorDisappear() {
        pinSettleTask?.cancel()
        pinSettleTask = nil
        // Defer the write off the LazyVStack layout pass; same rationale as
        // the original Task-wrapped writes — direct mutation here triggers
        // "modifying state during view update".
        Task { @MainActor in
            if isPinnedToBottom {
                isPinnedToBottom = false
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: ChatScrollAnimation.scrollDuration)) {
                action()
            }
        } else {
            action()
        }
    }
}
