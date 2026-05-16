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

enum ChatScrollBackend {
    case automatic
    case swiftUI
    case nativeSingleHost
    case nativeTable
    case nativeStack
}

struct ChatScrollView<RowContent: View>: View {
    @Binding var isPinnedToBottom: Bool
    @Binding var scrollToBottomRequest: ScrollToBottomRequest

    private let rows: [ChatTableRowModel]
    private let isStreaming: Bool
    private let backend: ChatScrollBackend
    private let onReachTop: (() -> Void)?
    private let onScrollAnimationComplete: ((Int) -> Void)?
    private let rowContent: (ChatTableRowModel) -> RowContent

    init(
        rows: [ChatTableRowModel],
        isPinnedToBottom: Binding<Bool>,
        scrollToBottomRequest: Binding<ScrollToBottomRequest>,
        isStreaming: Bool = false,
        backend: ChatScrollBackend = .automatic,
        onReachTop: (() -> Void)? = nil,
        onScrollAnimationComplete: ((Int) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (ChatTableRowModel) -> RowContent
    ) {
        self.rows = rows
        _isPinnedToBottom = isPinnedToBottom
        _scrollToBottomRequest = scrollToBottomRequest
        self.isStreaming = isStreaming
        self.backend = backend
        self.onReachTop = onReachTop
        self.onScrollAnimationComplete = onScrollAnimationComplete
        self.rowContent = rowContent
    }

    var body: some View {
        switch resolvedBackend {
            case .automatic,
                    .swiftUI:
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
                    rows: rows,
                    isPinnedToBottom: $isPinnedToBottom,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    isStreaming: isStreaming,
                    onReachTop: onReachTop,
                    onScrollAnimationComplete: onScrollAnimationComplete,
                    rowContent: rowContent
                )

            case .nativeTable:
                NativeChatTableView(
                    rows: rows,
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

    private var resolvedBackend: ChatScrollBackend {
        guard backend == .automatic else { return backend }

#if os(macOS)
#if DEBUG
        return AIChatRenderDebug.useStackMessageListHost ? .nativeStack : .nativeTable
#else
        return .nativeStack
#endif
#else
        return .swiftUI
#endif
    }

    private var contentRevision: String {
        rows
            .map { "\($0.id):\($0.signature)" }
            .joined(separator: "|")
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
