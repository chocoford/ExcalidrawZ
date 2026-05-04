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

/// SwiftUI-native chat scroll view backed by `ScrollView` + `LazyVStack`.
/// Replaces the previous `List`-backed implementation — no row diffing surprises,
/// no list-only chrome, and we can control layout directly.
struct ChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    /// When true, every content height growth force-scrolls to the bottom regardless
    /// of pin state. Used while the assistant is streaming — the user explicitly
    /// asked for "always follow bottom during answer".
    private let followBottom: Bool
    private let content: Content
    private let bottomThreshold: CGFloat

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        followBottom: Bool = false,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.followBottom = followBottom
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    var body: some View {
        ChatScrollContainer(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            followBottom: followBottom,
            bottomThreshold: bottomThreshold
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
    private let followBottom: Bool
    private let content: Content
    private let bottomThreshold: CGFloat

    private let coordinateSpaceName = "chat-scroll-view"
    private let bottomAnchorID = "chat-scroll-bottom-anchor"

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        followBottom: Bool,
        bottomThreshold: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.followBottom = followBottom
        self.bottomThreshold = bottomThreshold
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Offset reader sits at the top of the lazy stack so its
                // `.minY` in the named coordinate space directly tracks how far
                // we've scrolled down from the start of content.
                offsetReader

                LazyVStack(spacing: 0) {
                    content

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .background(contentHeightReader)
            }
            .coordinateSpace(name: coordinateSpaceName)
            .background(viewportHeightReader)
            .onPreferenceChange(ChatScrollContentHeightKey.self) { newValue in
                contentHeight = newValue
                // Don't call `updatePinnedState()` here. When content grows, the
                // *new* contentHeight pairs with the *old* scrollOffset → the
                // computed distance temporarily exceeds the threshold and pin
                // would flip false, suppressing the very scroll we want.
                // We let the next offset preference (after the scroll lands)
                // re-evaluate pin instead.
                if followBottom || isPinnedToBottom {
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onPreferenceChange(ChatScrollViewportHeightKey.self) { newValue in
                viewportHeight = newValue
                updatePinnedState()
            }
            .onPreferenceChange(ChatScrollOffsetKey.self) { newValue in
                scrollOffset = max(0, newValue)
                updatePinnedState()
            }
            .onChange(of: scrollToBottomRequest.token) { _ in
                scrollToBottom(proxy, animated: scrollToBottomRequest.animated)
            }
            .onAppear {
                updatePinnedState()
            }
        }
    }

    private var offsetReader: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named(coordinateSpaceName)).minY
            Color.clear.preference(key: ChatScrollOffsetKey.self, value: -minY)
        }
        .frame(height: 0)
    }

    private var contentHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ChatScrollContentHeightKey.self, value: proxy.size.height)
        }
    }

    private var viewportHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ChatScrollViewportHeightKey.self, value: proxy.size.height)
        }
    }

    private func updatePinnedState() {
        let maxOffset = max(0, contentHeight - viewportHeight)
        let distanceToBottom = maxOffset - scrollOffset
        let pinned = distanceToBottom <= bottomThreshold
        if pinned != isPinnedToBottom {
            isPinnedToBottom = pinned
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }
}

// MARK: - Preference keys

private struct ChatScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatScrollViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
