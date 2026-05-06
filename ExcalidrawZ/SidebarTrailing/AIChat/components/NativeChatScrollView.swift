//
//  NativeChatScrollView.swift
//  ExcalidrawZ
//
//  AppKit/UIKit-backed alternative to `ChatScrollView`. Drop-in: same
//  init signature, same `isPinnedToBottom` binding semantics, same
//  `ScrollToBottomRequest` token, same `ChatScrollRow` row chrome.
//
//  Why bother: SwiftUI `ScrollView` + `LazyVStack` exhibits a
//  measurement ↔ scroll feedback loop on long chats — `proxy.scrollTo`
//  triggers re-measure, the re-measure perturbs the scroll position,
//  scrollTo runs again on the next loop tick. With heavy streaming and
//  many tool cards already on screen this can spike the main thread to
//  100% CPU until the app becomes unresponsive.
//
//  This implementation sidesteps the loop by:
//  - Hosting the SwiftUI content tree inside a single `NSHostingView` /
//    `UIHostingController` placed in a native scroll view.
//  - Pin-to-bottom is observed *passively* off `clipView.bounds`
//    (macOS) / `contentOffset` (iOS). No polling.
//  - Auto-follow during streaming triggers off `documentView.frame` /
//    `contentSize` growth — pushed only when content actually grew,
//    not in an 80 ms timer. The pin decision uses the *prior*
//    document height so a growth-triggered scrollTo doesn't read its
//    own side-effect as "user scrolled away".
//
//  Trade-off: the whole content tree is a single hosting view, so any
//  `LazyVStack` *inside* the content still owns its own visible-region
//  windowing. The win here is removing the feedback loop and giving up
//  `ScrollViewProxy.scrollTo` polling — not getting cell recycling.
//  For order-of-magnitude scaling beyond a few thousand rows a
//  `UICollectionView` cell-per-row design would be the next step, but
//  that breaks the `@ViewBuilder content` API which call sites depend on.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct NativeChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
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
        #if os(macOS)
        AppKitChatScrollHost(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming,
            content: wrappedContent
        )
        #elseif os(iOS)
        UIKitChatScrollHost(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming,
            content: wrappedContent
        )
        #else
        EmptyView()
        #endif
    }

    /// Mirrors the chrome that `ChatScrollView`'s LazyVStack applies:
    /// 10 pt horizontal gutter + a 20 pt clear tail so the last row
    /// doesn't sit flush against the bottom edge.
    private var wrappedContent: some View {
        VStack(spacing: 0) {
            content
            Color.clear.frame(height: 20)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - macOS

#if os(macOS)

private struct AppKitChatScrollHost<Content: View>: NSViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    let isStreaming: Bool
    let content: Content

    /// Inherits from `NSObject` so the `@objc` selectors below are
    /// callable by `NotificationCenter` (selector-based observers
    /// require Objective-C dispatch).
    final class Coordinator: NSObject {
        var isPinnedToBottom: Binding<Bool>
        var scrollToBottomRequest: Binding<ScrollToBottomRequest>
        var lastSeenToken: Int
        /// Last measured documentView height. We compare growth against
        /// *this* (not the live frame) when deciding whether to auto-follow,
        /// so the bounds observation triggered by our own scrollTo doesn't
        /// loop back into another auto-follow.
        var lastDocumentHeight: CGFloat = 0
        /// Last seen clip-view width. Drives explicit
        /// `invalidateIntrinsicContentSize()` calls on width changes — see
        /// `clipViewBoundsDidChange` for rationale.
        var lastClipWidth: CGFloat = 0
        let pinThreshold: CGFloat = 8
        weak var scrollView: NSScrollView?
        /// The actual `documentView` — flipped, so origin is top-left.
        weak var documentContainer: FlippedContainerView?
        /// The SwiftUI host inside the container; needed only for
        /// `rootView` updates from `updateNSView`.
        var hostingView: NSHostingView<Content>?

        init(
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>
        ) {
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.lastSeenToken = scrollToBottomRequest.wrappedValue.token
            super.init()
        }

        @objc func clipViewBoundsDidChange(_ note: Notification) {
            // NSHostingView has a "high-water-mark" bug: when the proposed
            // width shrinks (text wraps more, content needs more height),
            // it correctly reports a taller intrinsic size up to autolayout.
            // But when the width grows back (text wraps less, content
            // needs *less* height), it doesn't proactively re-report a
            // smaller size — the row stays stuck at the tall value.
            //
            // `invalidateIntrinsicContentSize()` alone isn't enough,
            // because NSHostingView won't necessarily re-ask SwiftUI for
            // a new preferred size unless its rootView changes. So we
            // run the whole song: invalidate the cache, mark every
            // layer needsLayout, then force autolayout to *actually*
            // run now (not at the end of the event loop) — that's what
            // pulls a fresh size out of SwiftUI in the same way
            // sending a new message does.
            if let scrollView, let hostingView, let documentContainer {
                let newWidth = scrollView.contentView.bounds.width
                if abs(newWidth - lastClipWidth) > 0.5 {
                    lastClipWidth = newWidth
                    hostingView.invalidateIntrinsicContentSize()
                    hostingView.needsLayout = true
                    documentContainer.needsLayout = true
                    scrollView.needsLayout = true
                    scrollView.layoutSubtreeIfNeeded()
                }
            }
            updatePinnedBinding()
        }

        @objc func documentViewFrameDidChange(_ note: Notification) {
            guard let scrollView, let documentContainer else { return }
            let newHeight = documentContainer.frame.height
            let oldHeight = lastDocumentHeight

            if oldHeight == 0 {
                // First real measurement after layout. If host says we
                // start pinned (the default), snap once.
                if isPinnedToBottom.wrappedValue {
                    scrollToBottom(animated: false)
                }
            } else if newHeight > oldHeight {
                // Compute pin against the *old* doc height — content has
                // grown but the clipView hasn't moved yet, so the new
                // distance-to-bottom is artificially large. We want
                // "was the user at the bottom before this growth."
                let visibleMaxY = scrollView.contentView.bounds.maxY
                let visibleHeight = scrollView.contentView.bounds.height
                let wasPinned = oldHeight <= visibleHeight ||
                    visibleMaxY >= oldHeight - pinThreshold
                if wasPinned {
                    scrollToBottom(animated: false)
                }
            }
            lastDocumentHeight = newHeight
            // After height change, reconcile the pin binding against the
            // (possibly-just-mutated) state.
            updatePinnedBinding()
        }

        private func updatePinnedBinding() {
            guard let scrollView, let documentContainer else { return }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = documentContainer.frame.height
            let pinned = docHeight <= visibleHeight ||
                visibleMaxY >= docHeight - pinThreshold
            // Defer the write off the AppKit notification to avoid
            // SwiftUI's "Modifying state during view update" warning.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isPinnedToBottom.wrappedValue != pinned {
                    self.isPinnedToBottom.wrappedValue = pinned
                }
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView, let documentContainer else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let target = NSPoint(
                x: 0,
                y: max(0, documentContainer.frame.height - visibleHeight)
            )
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    scrollView.contentView.animator().setBoundsOrigin(target)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(target)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // The `documentView` is a flipped container; the SwiftUI host
        // sits inside it. We can't subclass `NSHostingView` to flip
        // it directly because `isFlipped` is non-open, so we wrap.
        let container = FlippedContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.postsFrameChangedNotifications = true

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)

        scrollView.documentView = container

        // Container fills clipView width; height grows from its
        // sole subview's intrinsic content size (NSHostingView).
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // NSClipView doesn't post bounds changes by default.
        scrollView.contentView.postsBoundsChangedNotifications = true

        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        coordinator.documentContainer = container
        coordinator.hostingView = hosting

        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.documentViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: container
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Refresh content & binding refs (SwiftUI hands us new bindings
        // each update; the Coordinator persists across them).
        context.coordinator.hostingView?.rootView = content
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest

        let token = scrollToBottomRequest.token
        if token != context.coordinator.lastSeenToken {
            context.coordinator.lastSeenToken = token
            let animated = scrollToBottomRequest.animated
            // Defer one tick: SwiftUI may not have flushed the new
            // hosting layout yet, so docHeight could still be stale.
            DispatchQueue.main.async { [coordinator = context.coordinator] in
                coordinator.scrollToBottom(animated: animated)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

/// Flipped container that sits as the scroll view's `documentView`.
/// We can't override `NSHostingView.isFlipped` directly (`non-open`
/// in SwiftUI's module), so we host the SwiftUI content inside this
/// flipped wrapper instead. Origin ends up top-left, matching
/// SwiftUI's mental model.
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

#endif

// MARK: - iOS

#if os(iOS)

private struct UIKitChatScrollHost<Content: View>: UIViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    let isStreaming: Bool
    let content: Content

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var isPinnedToBottom: Binding<Bool>
        var scrollToBottomRequest: Binding<ScrollToBottomRequest>
        var lastSeenToken: Int
        var lastContentHeight: CGFloat = 0
        let pinThreshold: CGFloat = 8
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<Content>?
        /// While true, swallow `scrollViewDidScroll` pin updates — used
        /// to mask the scroll-position changes that our own
        /// `setContentOffset` triggers.
        var isProgrammaticScroll: Bool = false

        init(
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>
        ) {
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.lastSeenToken = scrollToBottomRequest.wrappedValue.token
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll else { return }
            updatePinnedBinding()
        }

        private func updatePinnedBinding() {
            guard let scrollView else { return }
            let docHeight = scrollView.contentSize.height
            let visibleHeight = scrollView.bounds.height
            let maxY = scrollView.contentOffset.y + visibleHeight
            let pinned = docHeight <= visibleHeight ||
                maxY >= docHeight - pinThreshold
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isPinnedToBottom.wrappedValue != pinned {
                    self.isPinnedToBottom.wrappedValue = pinned
                }
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView else { return }
            let visibleHeight = scrollView.bounds.height
            let target = max(0, scrollView.contentSize.height - visibleHeight)
            isProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
            // Allow any in-flight delegate callbacks from the programmatic
            // scroll to drain before reopening the pin observer.
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.3 : 0.05)) { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        func contentSizeDidChange(oldSize: CGSize, newSize: CGSize) {
            guard let scrollView else { return }
            let oldHeight = oldSize.height
            let newHeight = newSize.height

            if lastContentHeight == 0 {
                if isPinnedToBottom.wrappedValue {
                    scrollToBottom(animated: false)
                }
            } else if newHeight > oldHeight {
                let visibleHeight = scrollView.bounds.height
                let visibleMaxY = scrollView.contentOffset.y + visibleHeight
                let wasPinned = oldHeight <= visibleHeight ||
                    visibleMaxY >= oldHeight - pinThreshold
                if wasPinned {
                    scrollToBottom(animated: false)
                }
            }
            lastContentHeight = newHeight
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest
        )
    }

    func makeUIView(context: Context) -> ChatScrollHostUIView {
        let scrollView = ChatScrollHostUIView()
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.contentSizeChangeHandler = { [weak coordinator = context.coordinator] oldSize, newSize in
            coordinator?.contentSizeDidChange(oldSize: oldSize, newSize: newSize)
        }

        let hosting = UIHostingController(rootView: content)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        if #available(iOS 16.0, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }
        scrollView.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosting.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingController = hosting
        return scrollView
    }

    func updateUIView(_ scrollView: ChatScrollHostUIView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest

        let token = scrollToBottomRequest.token
        if token != context.coordinator.lastSeenToken {
            context.coordinator.lastSeenToken = token
            let animated = scrollToBottomRequest.animated
            DispatchQueue.main.async { [coordinator = context.coordinator] in
                coordinator.scrollToBottom(animated: animated)
            }
        }
    }
}

/// `UIScrollView` subclass that surfaces `contentSize` changes via callback.
/// KVO would also work; the property override is simpler and avoids the
/// observer-deinit dance.
private final class ChatScrollHostUIView: UIScrollView {
    var contentSizeChangeHandler: ((CGSize, CGSize) -> Void)?

    override var contentSize: CGSize {
        didSet {
            if oldValue != contentSize {
                contentSizeChangeHandler?(oldValue, contentSize)
            }
        }
    }
}

#endif
