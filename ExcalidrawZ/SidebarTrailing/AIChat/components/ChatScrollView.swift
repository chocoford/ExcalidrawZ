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

struct ChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let content: Content
    private let bottomThreshold: CGFloat

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    var body: some View {
        let fixedContent = ChatScrollContent(content: content)
        ListChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            bottomThreshold: bottomThreshold
        ) {
            fixedContent
        }
    }
}

struct ChatScrollRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.modifier(ChatScrollRowStyle())
    }
}

private struct ChatScrollContent<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ListChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let content: Content
    private let bottomThreshold: CGFloat
    private let bottomAnchorID = "chat-scroll-bottom-anchor"

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                content
                ChatScrollBottomAnchor(
                    isPinnedToBottom: $isPinnedToBottom,
                    id: bottomAnchorID
                )
            }
            .listStyle(.plain)
            .applyScrollContentBackgroundHidden()
            .onChange(of: scrollToBottomRequest.token) { _ in
                scrollToBottom(proxy, animated: scrollToBottomRequest.animated)
            }
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

private struct ChatScrollBottomAnchor: View {
    @Binding var isPinnedToBottom: Bool
    let id: String

    var body: some View {
        Color.clear
            .frame(height: 1)
            .id(id)
            .onAppear {
                isPinnedToBottom = true
            }
            .onDisappear {
                isPinnedToBottom = false
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .applyListRowSeparatorHidden()
            .listRowBackground(Color.clear)
    }
}

private extension View {
    @ViewBuilder
    func applyListRowSeparatorHidden() -> some View {
        if #available(macOS 12.0, iOS 15.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyScrollContentBackgroundHidden() -> some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

private struct ChatScrollRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 12.0, iOS 15.0, *) {
            content
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            content
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
    }
}

#if canImport(AppKit)
import AppKit

private struct AppKitChatScrollView<Content: View>: NSViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let content: Content
    private let bottomThreshold: CGFloat

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPinnedToBottom: $isPinnedToBottom, bottomThreshold: bottomThreshold)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none

        let hostingView = NSHostingView(rootView: content)
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = [.intrinsicContentSize]
        }
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.postsFrameChangedNotifications = true
        hostingView.setContentHuggingPriority(.required, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)
        scrollView.documentView = hostingView

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        context.coordinator.attach(to: scrollView, hostingView: hostingView)
        context.coordinator.layoutDocumentView(scrollView: scrollView, force: true)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
        }
        context.coordinator.layoutDocumentView(scrollView: nsView, force: true)
        if context.coordinator.lastRequestToken != scrollToBottomRequest.token {
            context.coordinator.lastRequestToken = scrollToBottomRequest.token
            context.coordinator.scrollToBottom(nsView, animated: scrollToBottomRequest.animated)
        }
        context.coordinator.updatePinnedState(scrollView: nsView)
    }

    final class Coordinator: NSObject {
        private var isPinnedToBottom: Binding<Bool>
        private let bottomThreshold: CGFloat
        weak var scrollView: NSScrollView?
        weak var hostingView: NSHostingView<Content>?
        var lastRequestToken: Int = 0
        private var lastKnownWidth: CGFloat = 0
        private var lastKnownHeight: CGFloat = 0

        init(isPinnedToBottom: Binding<Bool>, bottomThreshold: CGFloat) {
            self.isPinnedToBottom = isPinnedToBottom
            self.bottomThreshold = bottomThreshold
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to scrollView: NSScrollView, hostingView: NSHostingView<Content>) {
            self.scrollView = scrollView
            self.hostingView = hostingView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            if let documentView = scrollView.documentView {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(documentViewFrameDidChange(_:)),
                    name: NSView.frameDidChangeNotification,
                    object: documentView
                )
            }
        }

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            layoutDocumentView(scrollView: scrollView, force: false)
            updatePinnedState(scrollView: scrollView)
        }

        @objc private func documentViewFrameDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            if isPinnedToBottom.wrappedValue {
                scrollToBottom(scrollView, animated: false)
            }
        }

        func updatePinnedState(scrollView: NSScrollView) {
            let pinned = isNearBottom(scrollView)
            if pinned != isPinnedToBottom.wrappedValue {
                isPinnedToBottom.wrappedValue = pinned
            }
        }

        func layoutDocumentView(scrollView: NSScrollView, force: Bool) {
            guard let hostingView else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0 else { return }
            hostingView.frame.size.width = width
            hostingView.layoutSubtreeIfNeeded()
            let fitting = hostingView.fittingSize
            let height = max(1, fitting.height)
            if !force,
               abs(width - lastKnownWidth) < 0.5,
               abs(height - lastKnownHeight) < 0.5 {
                return
            }
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            scrollView.documentView?.frame = hostingView.frame
            lastKnownWidth = width
            lastKnownHeight = height
        }

        func scrollToBottom(_ scrollView: NSScrollView, animated: Bool) {
            guard let documentView = scrollView.documentView else { return }
            let contentHeight = documentView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxOffsetY = max(0, contentHeight - visibleHeight)
            let target = NSPoint(x: 0, y: maxOffsetY)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    scrollView.contentView.animator().setBoundsOrigin(target)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(target)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let contentHeight = documentView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxOffsetY = max(0, contentHeight - visibleHeight)
            let currentOffsetY = scrollView.contentView.bounds.origin.y
            return (maxOffsetY - currentOffsetY) <= bottomThreshold
        }
    }
}
#elseif canImport(UIKit)
import UIKit

private final class ChatHostingScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private struct UIKitChatScrollView<Content: View>: UIViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let content: Content
    private let bottomThreshold: CGFloat

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPinnedToBottom: $isPinnedToBottom, bottomThreshold: bottomThreshold)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ChatHostingScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.layoutContent(scrollView: scrollView, force: false)
        }

        let hostingController = UIHostingController(rootView: content)
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = [.intrinsicContentSize]
        }
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.backgroundColor = .clear
        hostingController.view.setContentHuggingPriority(.required, for: .vertical)
        hostingController.view.setContentCompressionResistancePriority(.required, for: .vertical)
        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController

        context.coordinator.attach(to: scrollView)
        context.coordinator.layoutContent(scrollView: scrollView, force: true)
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if let hostingController = context.coordinator.hostingController {
            hostingController.rootView = content
            hostingController.view.invalidateIntrinsicContentSize()
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
        }
        context.coordinator.layoutContent(scrollView: uiView, force: true)
        if context.coordinator.lastRequestToken != scrollToBottomRequest.token {
            context.coordinator.lastRequestToken = scrollToBottomRequest.token
            context.coordinator.scrollToBottom(uiView, animated: scrollToBottomRequest.animated)
        }
        context.coordinator.updatePinnedState(scrollView: uiView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private var isPinnedToBottom: Binding<Bool>
        private let bottomThreshold: CGFloat
        weak var scrollView: UIScrollView?
        var lastRequestToken: Int = 0
        var hostingController: UIHostingController<Content>?
        private var lastKnownWidth: CGFloat = 0
        private var lastKnownHeight: CGFloat = 0

        init(isPinnedToBottom: Binding<Bool>, bottomThreshold: CGFloat) {
            self.isPinnedToBottom = isPinnedToBottom
            self.bottomThreshold = bottomThreshold
        }

        deinit {
        }

        func attach(to scrollView: UIScrollView) {
            self.scrollView = scrollView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updatePinnedState(scrollView: scrollView)
        }

        func updatePinnedState(scrollView: UIScrollView) {
            let pinned = isNearBottom(scrollView)
            if pinned != isPinnedToBottom.wrappedValue {
                isPinnedToBottom.wrappedValue = pinned
            }
        }

        func layoutContent(scrollView: UIScrollView, force: Bool) {
            guard let hostingController else { return }
            let width = scrollView.bounds.width
            guard width > 0 else { return }
            let fitting: CGSize
            if #available(iOS 16.0, *) {
                fitting = hostingController.sizeThatFits(
                    in: CGSize(width: width, height: .greatestFiniteMagnitude)
                )
            } else {
                fitting = hostingController.view.sizeThatFits(
                    CGSize(width: width, height: .greatestFiniteMagnitude)
                )
            }
            let height = max(1, fitting.height)
            if !force,
               abs(width - lastKnownWidth) < 0.5,
               abs(height - lastKnownHeight) < 0.5 {
                return
            }
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            scrollView.contentSize = CGSize(width: width, height: height)
            lastKnownWidth = width
            lastKnownHeight = height
        }

        func scrollToBottom(_ scrollView: UIScrollView, animated: Bool) {
            let inset = scrollView.adjustedContentInset
            let contentHeight = scrollView.contentSize.height
            let visibleHeight = max(0, scrollView.bounds.height - inset.top - inset.bottom)
            let maxOffsetY = max(-inset.top, contentHeight - visibleHeight + inset.bottom)
            let target = CGPoint(x: 0, y: maxOffsetY)
            scrollView.setContentOffset(target, animated: animated)
        }

        private func isNearBottom(_ scrollView: UIScrollView) -> Bool {
            let inset = scrollView.adjustedContentInset
            let contentHeight = scrollView.contentSize.height
            let visibleHeight = max(0, scrollView.bounds.height - inset.top - inset.bottom)
            let maxOffsetY = max(-inset.top, contentHeight - visibleHeight + inset.bottom)
            let currentOffsetY = scrollView.contentOffset.y
            return (maxOffsetY - currentOffsetY) <= bottomThreshold
        }
    }
}
#else
private struct SwiftUIChatScrollView<Content: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    private let content: Content
    private let bottomThreshold: CGFloat

    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private let coordinateSpaceName = "chat-scroll-view"
    private let bottomAnchorID = "chat-scroll-bottom-anchor"

    init(
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        bottomThreshold: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.content = content()
        self.bottomThreshold = bottomThreshold
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    scrollOffsetReader
                    content
                    Color.clear.frame(height: 1).id(bottomAnchorID)
                }
                .background(contentHeightReader)
            }
            .coordinateSpace(name: coordinateSpaceName)
            .background(scrollViewHeightReader)
            .onPreferenceChange(ChatScrollViewContentHeightKey.self) { newValue in
                contentHeight = newValue
                updatePinnedState()
            }
            .onPreferenceChange(ChatScrollViewHeightKey.self) { newValue in
                scrollViewHeight = newValue
                updatePinnedState()
            }
            .onPreferenceChange(ChatScrollViewOffsetKey.self) { newValue in
                scrollOffset = max(0, newValue)
                updatePinnedState()
            }
            .onChange(of: scrollToBottomRequest.token) { _ in
                scrollToBottom(proxy, animated: scrollToBottomRequest.animated)
            }
            .onChange(of: contentHeight) { _ in
                if isPinnedToBottom {
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onAppear {
                updatePinnedState()
            }
        }
    }

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named(coordinateSpaceName)).minY
            Color.clear.preference(key: ChatScrollViewOffsetKey.self, value: -minY)
        }
        .frame(height: 0)
    }

    private var contentHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ChatScrollViewContentHeightKey.self, value: proxy.size.height)
        }
    }

    private var scrollViewHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ChatScrollViewHeightKey.self, value: proxy.size.height)
        }
    }

    private func updatePinnedState() {
        let maxOffset = max(0, contentHeight - scrollViewHeight)
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

private struct ChatScrollViewContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChatScrollViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
