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
        var isStreaming: Bool
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
        /// Wall-clock time the host mounted. Combined with
        /// `initialSettlingDuration`, defines a window after mount where
        /// growth-driven snaps to bottom run unconditionally — covers the
        /// case where the first frame change reports a partial height
        /// (markdown render, image load, async layout) and subsequent
        /// growth needs to keep us pinned without going through the
        /// streaming gate.
        let mountedAt: Date = Date()
        let initialSettlingDuration: TimeInterval = 0.3
        let pinThreshold: CGFloat = 8
        weak var scrollView: NSScrollView?
        /// The actual `documentView` — flipped, so origin is top-left.
        weak var documentContainer: FlippedContainerView?
        /// The SwiftUI host inside the container; needed only for
        /// `rootView` updates from `updateNSView`.
        var hostingView: NSHostingView<Content>?
        var isProgrammaticScrollPendingToBottom: Bool = false
        var deferredScrollToBottomWorkItem: DispatchWorkItem?

        init(
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>,
            isStreaming: Bool
        ) {
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.isStreaming = isStreaming
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
            guard let documentContainer else { return }
            let newHeight = documentContainer.frame.height
            let oldHeight = lastDocumentHeight
            let withinInitialSettling =
                Date().timeIntervalSince(mountedAt) < initialSettlingDuration

            if oldHeight == 0 {
                // First real measurement after layout. If host says we
                // start pinned (the default), snap once.
                if isPinnedToBottom.wrappedValue {
                    scrollToBottom(animated: false)
                }
            } else if withinInitialSettling,
                      newHeight > oldHeight,
                      isPinnedToBottom.wrappedValue {
                // Initial layout is still settling — async content
                // (markdown render passes, image decoding, late-mounting
                // rows) keeps growing the document. Snap without
                // animation so the user sees a stable "at bottom" state
                // rather than a frozen mid-scroll position.
                scrollToBottom(animated: false)
            } else if newHeight > oldHeight,
                      ((isStreaming && isPinnedToBottom.wrappedValue) ||
                       isProgrammaticScrollPendingToBottom) {
                // Auto-follow growth in two cases:
                //  1. We're streaming AND the user is currently pinned at the
                //     bottom — keeps the live message glued to the viewport.
                //  2. A programmatic pin-to-bottom is already in flight (post-
                //     send `LoadingMessageRow` lands one frame after the user
                //     message; we re-target the in-flight animation so the
                //     pin doesn't escape).
                // Outside streaming we deliberately do *not* auto-scroll on
                // growth — expanding tool cards / late-mounting library
                // content shouldn't yank the user's scroll position.
                scrollToBottom(animated: true)
                scheduleDeferredScrollToBottom(animated: true)
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
            isProgrammaticScrollPendingToBottom = true
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = ChatScrollAnimation.scrollDuration
                    scrollView.contentView.animator().setBoundsOrigin(target)
                } completionHandler: { [weak self] in
                    self?.isProgrammaticScrollPendingToBottom = false
                }
            } else {
                scrollView.contentView.setBoundsOrigin(target)
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticScrollPendingToBottom = false
                }
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func scheduleDeferredScrollToBottom(animated: Bool) {
            deferredScrollToBottomWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.scrollToBottom(animated: animated)
            }
            deferredScrollToBottomWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming
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
        // Force overlay scroller style regardless of the user's
        // "Show scroll bars" pref. Legacy scrollers steal ~15 pt of
        // width when they appear, which can knock content like a
        // wrapping Markdown body across a line boundary — that
        // changes the content's intrinsic height, which changes
        // whether scrollers are needed at all, which loops. Overlay
        // scrollers float over the content and don't perturb width.
        scrollView.scrollerStyle = .overlay

        // Don't clip the document view to the scroll view's bounds —
        // we want chat rows to bleed past the top edge into the
        // inspector/toolbar chrome (translucent material draws over
        // them), matching SwiftUI's native `ScrollView` look. The
        // scroll geometry itself is unaffected: NSClipView still
        // tracks bounds for hit-testing and offset math, only
        // the visual clip is dropped.
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = false

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
        // Order matters: update the gate flags BEFORE pushing the new
        // rootView. `rootView = content` schedules a SwiftUI layout pass
        // that may emit `frameDidChange` synchronously; if `isStreaming`
        // is still the prior (false) value at that moment, the gate
        // would short-circuit the auto-follow. Setting the flag first
        // keeps the gate decision in sync with the content it observes.
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest
        context.coordinator.isStreaming = isStreaming
        context.coordinator.hostingView?.rootView = content

        let token = scrollToBottomRequest.token
        if token != context.coordinator.lastSeenToken {
            context.coordinator.lastSeenToken = token
            let animated = scrollToBottomRequest.animated
            // Defer one tick: SwiftUI may not have flushed the new
            // hosting layout yet, so docHeight could still be stale.
            DispatchQueue.main.async { [coordinator = context.coordinator] in
                coordinator.scrollToBottom(animated: animated)
                if animated {
                    coordinator.scheduleDeferredScrollToBottom(animated: true)
                }
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
        var isStreaming: Bool
        var lastSeenToken: Int
        var lastContentHeight: CGFloat = 0
        /// Mirrors the macOS settling window — see that path for the
        /// rationale. While inside this window, growth-driven snap to
        /// bottom runs unconditionally so partial first-paint heights
        /// don't leave the user mid-scroll.
        let mountedAt: Date = Date()
        let initialSettlingDuration: TimeInterval = 0.3
        let pinThreshold: CGFloat = 8
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<Content>?
        /// While true, swallow `scrollViewDidScroll` pin updates — used
        /// to mask the scroll-position changes that our own
        /// `setContentOffset` triggers.
        var isProgrammaticScroll: Bool = false
        var isProgrammaticScrollPendingToBottom: Bool = false
        var deferredScrollToBottomWorkItem: DispatchWorkItem?

        init(
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>,
            isStreaming: Bool
        ) {
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.isStreaming = isStreaming
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
            isProgrammaticScrollPendingToBottom = true
            scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
            // Allow any in-flight delegate callbacks from the programmatic
            // scroll to drain before reopening the pin observer.
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? ChatScrollAnimation.scrollDuration + 0.1 : 0.05)) { [weak self] in
                self?.isProgrammaticScroll = false
                self?.isProgrammaticScrollPendingToBottom = false
            }
        }

        func contentSizeDidChange(oldSize: CGSize, newSize: CGSize) {
            guard let scrollView else { return }
            let oldHeight = oldSize.height
            let newHeight = newSize.height

            let withinInitialSettling =
                Date().timeIntervalSince(mountedAt) < initialSettlingDuration

            if lastContentHeight == 0 {
                if isPinnedToBottom.wrappedValue {
                    scrollToBottom(animated: false)
                }
            } else if withinInitialSettling,
                      newHeight > oldHeight,
                      isPinnedToBottom.wrappedValue {
                scrollToBottom(animated: false)
            } else if newHeight > oldHeight,
                      ((isStreaming && isPinnedToBottom.wrappedValue) ||
                       isProgrammaticScrollPendingToBottom) {
                // Mirrors the macOS gate: auto-follow growth only while
                // streaming (and pinned), or while a pin-to-bottom animation
                // is already in flight. Outside streaming, growth from
                // tool-card expand / library load doesn't auto-scroll.
                scrollToBottom(animated: true)
                scheduleDeferredScrollToBottom(animated: true)
            }
            lastContentHeight = newHeight
            updatePinnedBinding()
        }

        func scheduleDeferredScrollToBottom(animated: Bool) {
            deferredScrollToBottomWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.scrollToBottom(animated: animated)
            }
            deferredScrollToBottomWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming
        )
    }

    func makeUIView(context: Context) -> ChatScrollHostUIView {
        let scrollView = ChatScrollHostUIView()
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        // Same as the macOS side: let chat rows bleed past the
        // top edge into surrounding chrome instead of getting a
        // hard clip line. The scroll math is unchanged.
        scrollView.clipsToBounds = false
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
        // Same ordering rationale as the macOS path — gate flags before
        // rootView so an immediate `contentSize` emission lands with the
        // correct streaming state.
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest
        context.coordinator.isStreaming = isStreaming
        context.coordinator.hostingController?.rootView = content

        let token = scrollToBottomRequest.token
        if token != context.coordinator.lastSeenToken {
            context.coordinator.lastSeenToken = token
            let animated = scrollToBottomRequest.animated
            DispatchQueue.main.async { [coordinator = context.coordinator] in
                coordinator.scrollToBottom(animated: animated)
                if animated {
                    coordinator.scheduleDeferredScrollToBottom(animated: true)
                }
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
