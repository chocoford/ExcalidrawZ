//
//  UserMessageBubble.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import SFSafeSymbols

/// Right-aligned chat bubble for a `user` role message, plus any attached
/// images and the per-message usage chip.
struct UserMessageBubble: View {
    enum ActionKind {
        case edit
        case revert

        var title: String {
            switch self {
                case .edit: String(localizable: .aiChatUserMessageActionEditTitle)
                case .revert: String(localizable: .aiChatUserMessageActionRevertTitle)
            }
        }

        var symbol: SFSymbol {
            switch self {
                case .edit: .pencil
                case .revert: .arrowUturnBackward
            }
        }

        var help: String {
            switch self {
                case .edit:
                    String(localizable: .aiChatUserMessageActionEditHelp)
                case .revert:
                    String(localizable: .aiChatUserMessageActionRevertHelp)
            }
        }
    }

    let content: ChatMessageContent
    /// Optional edit/revert handler — called with the user message's id.
    /// `actionKind == nil` hides the action entirely.
    var actionKind: ActionKind?
    var showsAction: Bool = true
    var isActionDisabled: Bool = false
    var onAction: ((String) -> Void)?

    @State private var isPresented = false
    @State private var isConfirmingRevert = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: isPresented ? 0 : 20)
            if isPresented {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        bubbleContents
                        // Inline action bar — right-aligned to match the
                        // bubble. Only renders when there's something
                        // useful in it.
                        if actionKind != nil, onAction != nil {
                            actionBar
                                .opacity(showsAction ? 1 : 0)
                                .allowsHitTesting(showsAction)
                                .animation(.smooth, value: showsAction)
                        }
                    }
                }
                .opacity(isPresented ? 1 : 0)
            }
        }
        .confirmationDialog(
            String(localizable: .aiChatRevertConfirmationDialogTitle),
            isPresented: $isConfirmingRevert,
            titleVisibility: .visible
        ) {
            Button(.localizable(.aiChatRevertConfirmationDialogButtonConfirm), role: .destructive) {
                onAction?(content.id)
            }
            Button(.localizable(.generalButtonCancel), role: .cancel) {}
        } message: {
            Text(localizable: .aiChatRevertConfirmationDialogMessage)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut) {
                    isPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 4) {
            if let actionKind, let onAction {
                Button {
                    switch actionKind {
                        case .edit:
                            onAction(content.id)
                        case .revert:
                            isConfirmingRevert = true
                    }
                } label: {
                    Label(actionKind.title, systemSymbol: actionKind.symbol)
                        .labelStyle(.iconOnly)
                        .font(.caption)
                }
                .buttonStyle(.text(size: .small, square: true))
                .foregroundStyle(.secondary)
                .disabled(isActionDisabled)
                .opacity(isActionDisabled ? 0 : 1)
                .animation(.smooth, value: isActionDisabled)
            }
        }
    }

    @MainActor @ViewBuilder
    private var bubbleContents: some View {

        let imageFiles = (content.files ?? []).filter { file in
            switch file {
                case .base64EncodedImage, .image:
                    return true
            }
        }
        if !imageFiles.isEmpty {
            HStack(spacing: 6) {
                ForEach(imageFiles, id: \.self) { file in
                    MessageImageView(file: file)
                }
            }
            .frame(height: 160)
        }
        
        if let text = content.content, !text.isEmpty {
            UserMessageTextBubble(text: text)
        }
    }
}

private struct UserMessageTextBubble: View {
    let text: String

    @State private var isShowingFullText = false

    private let maxVisibleCharacters = 900
    private let maxVisibleLines = 10

    private var visibleText: String {
        guard shouldTruncate else { return text }

        let lineLimitedText = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxVisibleLines)
            .joined(separator: "\n")

        let characterLimitedText = String(lineLimitedText.prefix(maxVisibleCharacters))
        return characterLimitedText.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var shouldTruncate: Bool {
        text.count > maxVisibleCharacters || text.split(separator: "\n", omittingEmptySubsequences: false).count > maxVisibleLines
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            contents
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.accentColor.gradient.secondary)
                }
        } else {
            contents
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.secondary.gradient)
                }
                
        }
    }

    private var contents: some View {
        VStack(alignment: .trailing, spacing: 6) {
            SmoothStreamingText(target: visibleText)

            if shouldTruncate {
                Button(.localizable(.generalButtonShowMore)) {
                    isShowingFullText = true
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.text(size: .small))
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .popover(isPresented: $isShowingFullText, arrowEdge: .trailing) {
            ScrollView {
                SmoothStreamingText(target: text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 360, idealWidth: 480, maxWidth: 560, minHeight: 180, idealHeight: 360, maxHeight: 520)
        }
    }
}
