//
//  NativeChatTableView.swift
//  ExcalidrawZ
//

import SwiftUI

struct ChatTableRowModel: Identifiable {
    enum Kind {
        case hiddenHistory(hiddenGroupCount: Int, isLoading: Bool)
        case group(MessageGroup)
        case assistantItem(AssistantRoundTableItem)
        case assistantAction(AssistantRoundTableAction)
        case transientError(id: UUID, message: String)
    }

    let id: String
    let signature: String
    let kind: Kind
}

#if os(macOS)
import AppKit

struct NativeChatTableView<RowContent: View>: NSViewRepresentable {
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

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [ChatTableRowModel]
        var rowContent: (ChatTableRowModel) -> RowContent
        var isPinnedToBottom: Binding<Bool>
        var scrollToBottomRequest: Binding<ScrollToBottomRequest>
        var isStreaming: Bool
        var onReachTop: (() -> Void)?
        var onScrollAnimationComplete: ((Int) -> Void)?
        var lastSeenToken: Int
        var inflightScrollToken: Int?
        var lastDocumentHeight: CGFloat = 0
        var lastClipWidth: CGFloat = 0
        var didNotifyReachTop = false
        var isPreservingTopLoadPosition = false
        var isProgrammaticScrollPendingToBottom = false
        var deferredScrollToBottomWorkItem: DispatchWorkItem?
        var endTopLoadPreservationWorkItem: DispatchWorkItem?
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?

        let mountedAt = Date()
        let initialSettlingDuration: TimeInterval = 2.0
        let pinThreshold: CGFloat = 8
        let topLoadThreshold: CGFloat = 80
        let topLoadResetThreshold: CGFloat = 180
        let columnIdentifier = NSUserInterfaceItemIdentifier("chat-row")

        init(
            rows: [ChatTableRowModel],
            rowContent: @escaping (ChatTableRowModel) -> RowContent,
            isPinnedToBottom: Binding<Bool>,
            scrollToBottomRequest: Binding<ScrollToBottomRequest>,
            isStreaming: Bool,
            onReachTop: (() -> Void)?,
            onScrollAnimationComplete: ((Int) -> Void)?
        ) {
            self.rows = rows
            self.rowContent = rowContent
            self.isPinnedToBottom = isPinnedToBottom
            self.scrollToBottomRequest = scrollToBottomRequest
            self.isStreaming = isStreaming
            self.onReachTop = onReachTop
            self.onScrollAnimationComplete = onScrollAnimationComplete
            self.lastSeenToken = scrollToBottomRequest.wrappedValue.token
            super.init()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let rowModel = rows[row]
            let identifier = NSUserInterfaceItemIdentifier("chat-row-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self)
                as? ChatTableCellView
                ?? ChatTableCellView()
            cell.identifier = identifier
            cell.configure(
                rowID: rowModel.id,
                signature: rowModel.signature,
                rootView: AnyView(
                    rowContent(rowModel)
                        .id(rowModel.id)
                        .environment(
                            \.aiChatTableRowWidth,
                            tableView.tableColumns.first?.width ?? tableView.bounds.width
                        )
                ),
                onHeightInvalidated: { [weak self, weak cell, weak tableView] in
                    guard let self, let cell, let tableView else { return }
                    self.scheduleHeightInvalidation(for: cell, in: tableView)
                }
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            ChatTableRowView()
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func updateRows(_ nextRows: [ChatTableRowModel], in tableView: NSTableView) {
            let previousRows = rows
            rows = nextRows

            let previousIDs = previousRows.map(\.id)
            let nextIDs = nextRows.map(\.id)
            if previousIDs == nextIDs {
                let changedRows = IndexSet(
                    nextRows.indices.filter { index in
                        previousRows[index].signature != nextRows[index].signature
                    }
                )
                if !changedRows.isEmpty {
                    tableView.reloadData(
                        forRowIndexes: changedRows,
                        columnIndexes: IndexSet(integer: 0)
                    )
                    tableView.noteHeightOfRows(withIndexesChanged: changedRows)
                }
            } else {
                tableView.reloadData()
                tableView.noteHeightOfRows(
                    withIndexesChanged: IndexSet(integersIn: 0..<nextRows.count)
                )
            }
        }

        @objc func clipViewBoundsDidChange(_ note: Notification) {
            lockHorizontalOffsetAndSyncWidth()
            updatePinnedBinding()
            notifyReachTopIfNeeded()
        }

        func lockHorizontalOffsetAndSyncWidth() {
            guard let scrollView, let tableView else { return }
            let clipView = scrollView.contentView

            let width = clipView.bounds.width
            if abs(width - lastClipWidth) > 0.5 {
                lastClipWidth = width
            }
            if abs((tableView.tableColumns.first?.width ?? 0) - width) > 0.5 {
                tableView.tableColumns.first?.width = width
            }
            if abs(tableView.frame.width - width) > 0.5 {
                tableView.setFrameSize(
                    NSSize(width: width, height: tableView.frame.height)
                )
            }
        }

        @objc func tableFrameDidChange(_ note: Notification) {
            guard let tableView else { return }
            let newHeight = tableView.bounds.height
            let oldHeight = lastDocumentHeight
            let withinInitialSettling =
                Date().timeIntervalSince(mountedAt) < initialSettlingDuration

            if oldHeight == 0 {
                if isPinnedToBottom.wrappedValue {
                    scrollToBottom(animated: false)
                }
            } else if isPreservingTopLoadPosition,
                      newHeight != oldHeight {
                preserveScrollPositionAfterTopLoad(delta: newHeight - oldHeight)
                scheduleEndTopLoadPreservation()
            } else if withinInitialSettling,
                      newHeight > oldHeight,
                      isPinnedToBottom.wrappedValue {
                scrollToBottom(animated: false)
            } else if newHeight > oldHeight,
                      ((isStreaming && isPinnedToBottom.wrappedValue) ||
                       isProgrammaticScrollPendingToBottom) {
                scrollToBottom(animated: true)
                scheduleDeferredScrollToBottom(animated: true)
            }

            lastDocumentHeight = newHeight
            updatePinnedBinding()
        }

        private func notifyReachTopIfNeeded() {
            guard let onReachTop, let scrollView, let tableView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            guard tableView.bounds.height > visibleHeight + topLoadThreshold else {
                didNotifyReachTop = false
                return
            }

            let minY = scrollView.contentView.bounds.minY
            if minY <= topLoadThreshold {
                guard !didNotifyReachTop else { return }
                didNotifyReachTop = true
                isPreservingTopLoadPosition = true
                DispatchQueue.main.async {
                    onReachTop()
                }
            } else if minY > topLoadResetThreshold {
                didNotifyReachTop = false
            }
        }

        private func preserveScrollPositionAfterTopLoad(delta: CGFloat) {
            guard delta != 0, let scrollView, let tableView else { return }
            let currentY = scrollView.contentView.bounds.origin.y
            let maxY = max(0, tableView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: 0, y: min(max(0, currentY + delta), maxY))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scheduleEndTopLoadPreservation() {
            endTopLoadPreservationWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.isPreservingTopLoadPosition = false
            }
            endTopLoadPreservationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }

        private func updatePinnedBinding() {
            guard let scrollView, let tableView else { return }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let visibleHeight = scrollView.contentView.bounds.height
            let docHeight = tableView.bounds.height
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
            guard let scrollView, let tableView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let target = NSPoint(
                x: 0,
                y: max(0, tableView.bounds.height - visibleHeight)
            )
            isProgrammaticScrollPendingToBottom = true
            let tokenAtStart = lastSeenToken
            inflightScrollToken = tokenAtStart
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = ChatScrollAnimation.scrollDuration
                    scrollView.contentView.animator().setBoundsOrigin(target)
                } completionHandler: { [weak self] in
                    self?.completeScroll(token: tokenAtStart)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(target)
                DispatchQueue.main.async { [weak self] in
                    self?.completeScroll(token: tokenAtStart)
                }
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func completeScroll(token: Int) {
            isProgrammaticScrollPendingToBottom = false
            if inflightScrollToken == token {
                inflightScrollToken = nil
                onScrollAnimationComplete?(token)
            }
        }

        func scheduleDeferredScrollToBottom(animated: Bool) {
            deferredScrollToBottomWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.scrollToBottom(animated: animated)
            }
            deferredScrollToBottomWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        private func scheduleHeightInvalidation(
            for cell: ChatTableCellView,
            in tableView: NSTableView
        ) {
            DispatchQueue.main.async { [weak tableView, weak cell] in
                guard let tableView, let cell else { return }
                let row = tableView.row(for: cell)
                guard row >= 0 else { return }
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rows: [],
            rowContent: rowContent,
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreaming,
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

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.selectionHighlightStyle = .none
        tableView.style = .fullWidth
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.postsFrameChangedNotifications = true
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let column = NSTableColumn(identifier: context.coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        column.minWidth = 0
        column.width = max(1, scrollView.contentView.bounds.width)
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        context.coordinator.lastClipWidth = scrollView.contentView.bounds.width

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.tableFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: tableView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = context.coordinator.tableView else { return }
        context.coordinator.rowContent = rowContent
        context.coordinator.isPinnedToBottom = $isPinnedToBottom
        context.coordinator.scrollToBottomRequest = $scrollToBottomRequest
        context.coordinator.isStreaming = isStreaming
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onScrollAnimationComplete = onScrollAnimationComplete

        context.coordinator.lockHorizontalOffsetAndSyncWidth()
        context.coordinator.updateRows(rows, in: tableView)

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

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

private final class ChatTableCellView: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?
    private var rowID: String?
    private var signature: String?

    func configure(
        rowID: String,
        signature: String,
        rootView: AnyView,
        onHeightInvalidated: @escaping () -> Void
    ) {
        let hostingView: NSHostingView<AnyView>
        if let existing = self.hostingView {
            hostingView = existing
        } else {
            let hosting = NSHostingView(rootView: rootView)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.hostingView = hosting
            hostingView = hosting
        }

        guard self.rowID != rowID || self.signature != signature else { return }
        self.rowID = rowID
        self.signature = signature
        hostingView.rootView = rootView
        onHeightInvalidated()
    }
}

private final class ChatTableRowView: NSTableRowView {
    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}
#endif
