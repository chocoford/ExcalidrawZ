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

struct ChatScrollView<RowContent: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest

    private let rows: [ChatScrollRowModel]
    private let rowRenderKey: (ChatScrollRowModel) -> String
    private let isStreaming: Bool
    private let configuration: ChatScrollConfiguration
    private let onReachTop: (() -> Void)?
    private let onScrollAnimationComplete: ((Int) -> Void)?
    private let rowContent: (ChatScrollRowModel) -> RowContent

    init(
        rows: [ChatScrollRowModel],
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        isStreaming: Bool = false,
        configuration: ChatScrollConfiguration = .automatic,
        rowRenderKey: @escaping (ChatScrollRowModel) -> String = { $0.id },
        onReachTop: (() -> Void)? = nil,
        onScrollAnimationComplete: ((Int) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (ChatScrollRowModel) -> RowContent
    ) {
        self.rows = rows
        self.rowRenderKey = rowRenderKey
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.isStreaming = isStreaming
        self.configuration = configuration
        self.onReachTop = onReachTop
        self.onScrollAnimationComplete = onScrollAnimationComplete
        self.rowContent = rowContent
    }

    var body: some View {
        switch configuration.backend {
            case .swiftUI:
                SwiftUIChatScrollView(
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming
                ) {
                    rowsContent
                }

#if os(macOS)
            case .nativeStack:
                NativeChatStackView(
                    rows: nativeRows,
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming,
                    onReachTop: onReachTop,
                    onScrollAnimationComplete: onScrollAnimationComplete,
                    rowContent: rowContent
                )

            case .nativeTable:
                NativeChatTableView(
                    rows: nativeRows,
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming,
                    onReachTop: onReachTop,
                    onScrollAnimationComplete: onScrollAnimationComplete,
                    rowContent: rowContent
                )
#else
            case .nativeStack,
                    .nativeTable:
                SwiftUIChatScrollView(
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming
                ) {
                    rowsContent
                }
#endif

            case .nativeSingleHost:
                NativeChatScrollView(
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming,
                    contentRevision: contentRevision,
                    onReachTop: onReachTop,
                    onScrollAnimationComplete: onScrollAnimationComplete
                ) {
                    rowsContent
                }
        }
    }

    private var contentRevision: String {
        nativeRows
            .map { "\($0.id):\($0.renderKey)" }
            .joined(separator: "|")
    }

    private var nativeRows: [NativeChatRowSnapshot] {
        rows.map { row in
            NativeChatRowSnapshot(
                model: row,
                renderKey: rowRenderKey(row)
            )
        }
    }

    private var rowsContent: some View {
        ForEach(rows) { row in
            rowContent(row)
                .id(row.id)
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
