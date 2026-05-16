//
//  NativeChatStackView.swift
//  ExcalidrawZ
//

import SwiftUI

#if os(macOS)
import AppKit

struct NativeChatStackView<RowContent: View>: NSViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest
    let rows: [ChatTableRowModel]
    let isStreaming: Bool
    let onReachTop: (() -> Void)?
    let onScrollAnimationComplete: ((Int) -> Void)?
    let rowContent: (ChatTableRowModel) -> RowContent

    init(
        rows: [ChatTableRowModel],
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        isStreaming: Bool = false,
        onReachTop: (() -> Void)? = nil,
        onScrollAnimationComplete: ((Int) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (ChatTableRowModel) -> RowContent
    ) {
        self.rows = rows
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.isStreaming = isStreaming
        self.onReachTop = onReachTop
        self.onScrollAnimationComplete = onScrollAnimationComplete
        self.rowContent = rowContent
    }

    final class Coordinator: NSObject {
        var rows: [ChatTableRowModel] = []
        var rowContent: (ChatTableRowModel) -> RowContent
        var isPinnedToBottom: Binding<Bool>
        var scrollToBottomRequest: Binding<ScrollToBottomRequest>
        var onReachTop: (() -> Void)?
        var onScrollAnimationComplete: ((Int) -> Void)?
        var lastSeenToken: Int
        var lastClipWidth: CGFloat = 0
        var didNotifyReachTop = false
        var hostingViewsByID: [String: NSHostingView<AnyView>] = [:]
        var signaturesByID: [String: String] = [:]
        weak var scrollView: NSScrollView?
        weak var stackView: FlippedChatStackView?

        let pinThreshold: CGFloat = 8
        let topLoadThreshold: CGFloat = 80
        let topLoadResetThreshold: CGFloat = 180

        init(
            rowContent: @escaping (ChatTableRowModel) -> RowContent,
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>,
            onReachTop: (() -> Void)?,
            onScrollAnimationComplete: ((Int) -> Void)?
        ) {
            self.rowContent = rowContent
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.onReachTop = onReachTop
            self.onScrollAnimationComplete = onScrollAnimationComplete
            self.lastSeenToken = scrollToBottomRequest.wrappedValue.token
            super.init()
        }

        func updateRows(_ nextRows: [ChatTableRowModel], in stackView: FlippedChatStackView) {
            let previousRows = rows
            let previousIDs = previousRows.map(\.id)
            let nextIDs = nextRows.map(\.id)
            rows = nextRows

            if previousIDs == nextIDs {
                for row in nextRows where signaturesByID[row.id] != row.signature {
                    updateHostingView(for: row, in: stackView)
                }
            } else if previousIDs.elementsEqual(nextIDs.prefix(previousIDs.count)) {
                for row in nextRows.prefix(previousRows.count)
                    where signaturesByID[row.id] != row.signature {
                    updateHostingView(for: row, in: stackView)
                }
                for row in nextRows.dropFirst(previousRows.count) {
                    appendHostingView(for: row, to: stackView)
                }
            } else {
                rebuildRows(nextRows, in: stackView)
            }

            stackView.needsLayout = true
        }

        func reconfigureAllRows(in stackView: FlippedChatStackView) {
            for row in rows {
                updateHostingView(for: row, in: stackView, force: true)
            }
            stackView.needsLayout = true
        }

        private func rebuildRows(
            _ rows: [ChatTableRowModel],
            in stackView: FlippedChatStackView
        ) {
            for subview in stackView.arrangedSubviews {
                stackView.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }

            hostingViewsByID.removeAll(keepingCapacity: true)
            signaturesByID.removeAll(keepingCapacity: true)

            for row in rows {
                appendHostingView(for: row, to: stackView)
            }
        }

        private func appendHostingView(
            for row: ChatTableRowModel,
            to stackView: FlippedChatStackView
        ) {
            let hostingView = NSHostingView(rootView: rootView(for: row, in: stackView))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(hostingView)
            hostingViewsByID[row.id] = hostingView
            signaturesByID[row.id] = row.signature
        }

        private func updateHostingView(
            for row: ChatTableRowModel,
            in stackView: FlippedChatStackView,
            force: Bool = false
        ) {
            guard let hostingView = hostingViewsByID[row.id] else {
                appendHostingView(for: row, to: stackView)
                return
            }

            guard force || signaturesByID[row.id] != row.signature else { return }
            hostingView.rootView = rootView(for: row, in: stackView)
            hostingView.invalidateIntrinsicContentSize()
            signaturesByID[row.id] = row.signature
        }

        private func rootView(
            for row: ChatTableRowModel,
            in stackView: FlippedChatStackView
        ) -> AnyView {
            let rowWidth = currentRowWidth(in: stackView)
            return AnyView(
                rowContent(row)
                    .id(row.id)
                    .environment(\.aiChatTableRowWidth, rowWidth)
                    .environment(\.aiChatUsesNativeRowHeightCache, false)
                    .frame(width: rowWidth, alignment: .topLeading)
            )
        }

        private func currentRowWidth(in stackView: FlippedChatStackView) -> CGFloat {
            if stackView.bounds.width > 1 {
                return stackView.bounds.width
            }
            if let scrollView, scrollView.contentView.bounds.width > 1 {
                return scrollView.contentView.bounds.width
            }
            return 1
        }

        @objc func clipViewBoundsDidChange(_ note: Notification) {
            syncWidthIfNeeded()
            updatePinnedBinding()
            notifyReachTopIfNeeded()
        }

        func syncWidthIfNeeded() {
            guard let scrollView, let stackView else { return }
            let width = scrollView.contentView.bounds.width
            guard abs(width - lastClipWidth) > 0.5 else { return }
            lastClipWidth = width
            reconfigureAllRows(in: stackView)
        }

        private func notifyReachTopIfNeeded() {
            guard let onReachTop, let scrollView, let stackView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            guard stackView.frame.height > visibleHeight + topLoadThreshold else {
                didNotifyReachTop = false
                return
            }

            let minY = scrollView.contentView.bounds.minY
            if minY <= topLoadThreshold {
                guard !didNotifyReachTop else { return }
                didNotifyReachTop = true
                DispatchQueue.main.async {
                    onReachTop()
                }
            } else if minY > topLoadResetThreshold {
                didNotifyReachTop = false
            }
        }

        private func updatePinnedBinding() {
            guard let scrollView, let stackView else { return }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = stackView.frame.height
            let pinned = docHeight <= visibleHeight ||
                visibleMaxY >= docHeight - pinThreshold
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isPinnedToBottom.wrappedValue != pinned {
                    self.isPinnedToBottom.wrappedValue = pinned
                }
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView, let stackView else { return }
            scrollView.layoutSubtreeIfNeeded()
            stackView.layoutSubtreeIfNeeded()
            let visibleHeight = scrollView.contentView.bounds.height
            let target = NSPoint(
                x: 0,
                y: max(0, stackView.frame.height - visibleHeight)
            )
            let tokenAtStart = lastSeenToken
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = ChatScrollAnimation.scrollDuration
                    scrollView.contentView.animator().setBoundsOrigin(target)
                } completionHandler: { [weak self] in
                    self?.onScrollAnimationComplete?(tokenAtStart)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(target)
                DispatchQueue.main.async { [weak self] in
                    self?.onScrollAnimationComplete?(tokenAtStart)
                }
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rowContent: rowContent,
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            onReachTop: onReachTop,
            onScrollAnimationComplete: onScrollAnimationComplete
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        scrollView.scrollerInsets = .init()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = false

        let stackView = FlippedChatStackView()
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stackView.detachesHiddenViews = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.wantsLayer = true
        stackView.layer?.masksToBounds = false

        scrollView.documentView = stackView
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.stackView = stackView
        context.coordinator.lastClipWidth = scrollView.contentView.bounds.width

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        AIChatRenderDebug.hit("NativeChatStackView.updateNSView")
        guard let stackView = context.coordinator.stackView else { return }
        context.coordinator.rowContent = rowContent
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onScrollAnimationComplete = onScrollAnimationComplete

        context.coordinator.syncWidthIfNeeded()
        context.coordinator.updateRows(rows, in: stackView)

        let token = scrollToBottomRequest.token
        if token != context.coordinator.lastSeenToken {
            context.coordinator.lastSeenToken = token
            let animated = scrollToBottomRequest.animated
            DispatchQueue.main.async { [coordinator = context.coordinator] in
                coordinator.scrollToBottom(animated: animated)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

final class FlippedChatStackView: NSStackView {
    override var isFlipped: Bool { true }
}
#endif
