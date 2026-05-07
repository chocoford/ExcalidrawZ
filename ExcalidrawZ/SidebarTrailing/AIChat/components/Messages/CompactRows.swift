//
//  CompactRows.swift
//  ExcalidrawZ
//
//  Row view for the synthetic "[Summary of earlier conversation]"
//  message LLMKit inserts after a compact run — distinct from a
//  normal user bubble because it represents the LLM's working memory
//  of rolled-up history rather than something the user typed.
//
//  We *don't* differentiate `isCompactedOut` rows from normal ones —
//  the user shouldn't have to reason about which messages are in the
//  LLM's working set. They render exactly like any other message via
//  the regular `MessageGroup.user` / `.assistantRound` paths.
//

import SwiftUI

import ChocofordUI
import LLMCore
import SFSafeSymbols
import MarkdownUI
import SmoothGradient

/// Card that surfaces the rolled-up "earlier conversation" summary.
/// Uses an archive-like glyph + "Earlier conversation" label so the
/// user can tell at a glance that this row replaces history rather
/// than continues it. Body collapses to 4 lines by default; tap the
/// header chevron to expand.
struct CompactSummaryRow: View {
    let content: ChatMessageContent

    @State private var isExpanded: Bool = false

    /// LLMKit prefixes the model output with `"[Summary of earlier
    /// conversation]\n\n"` so the LLM itself recognizes the role of
    /// the message in the next round. Strip that header off here so
    /// the user sees just the body text — they already know this is
    /// a summary from the chrome.
    private var displayText: String {
        let raw = content.content ?? ""
        let prefix = "[Summary of earlier conversation]"
        if raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw
    }
    
    @State private var contentHeight: CGFloat = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !displayText.isEmpty {
                ZStack(alignment: .top) {
                    Markdown(displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .readHeight($contentHeight)
                }
                .modifier(
                    CompactSummaryRowHeightModifier(height: isExpanded ? contentHeight : 80)
                )
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        if contentHeight > 150 {
                            ZStack {
                                if #available(macOS 14.0, *) {
                                    SmoothLinearGradient(
                                        from: .black,
                                        to: .clear,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                } else {
                                    LinearGradient(
                                        colors: [.black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            }
                            .frame(height: isExpanded ? 0 : 30)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator, lineWidth: 0.5)
                    }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemSymbol: .archiveboxFill)
                    .font(.caption)
                Text("Earlier conversation")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemSymbol: .chevronRight)
                    .font(.caption2)
                    .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CompactSummaryRowHeightModifier: Animatable, ViewModifier {
    
    init(height: CGFloat) {
        self.animatableData = height
    }
    
    var animatableData: CGFloat
    
    
    func body(content: Content) -> some View {
        content
            .frame(height: animatableData, alignment: .top)
    }
}
