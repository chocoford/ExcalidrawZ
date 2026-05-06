//
//  ToolEventCard.swift
//  ExcalidrawZ
//
//  Shared chassis for the tinted, collapsible "tool event" cards that
//  punctuate an assistant round (`ToolCallCard`, `ToolResultCard`, and any
//  future siblings). The chassis owns:
//
//   - tinted rounded background (`accent.opacity(0.1)` + 8pt corner)
//   - 12pt horizontal / 8pt vertical inset
//   - header row: chevron → SF Symbol icon → title (with optional shimmer)
//   - tap-to-toggle expand/collapse, the state held privately by the card
//
//  The expanded body is supplied by the caller. The chassis passes the
//  current `isExpanded` flag in so the body builder can decide what to
//  hide, what to keep pinned (e.g. tool-result image attachments, which
//  the result card surfaces regardless of expand state), and what to
//  show only on expand. We do NOT pad the body's leading edge here — the
//  caller can choose 22pt to align under the icon, or skip indentation
//  entirely (full-bleed media).
//
//  Style differences across consumers (icon, title, accent color,
//  shimmer-while-streaming) collapse into init parameters; everything
//  else is shared.
//

import SwiftUI
import SFSafeSymbols
import Shimmer

struct ToolEventCard<Content: View>: View {
    let icon: SFSymbol
    let title: String
    let accent: Color
    /// Pulsing shimmer on the title — used while a tool call is in flight
    /// so the user reads it as "busy" rather than "settled".
    var isShimmering: Bool = false
    /// Body builder. Receives the current expansion state so it can mix
    /// always-visible elements (images, summary) with collapse-on-fold
    /// elements (raw arguments, long text). Apply `.padding(.leading, 22)`
    /// inside the builder for the standard "indent under icon" alignment.
    @ViewBuilder var content: (_ isExpanded: Bool) -> Content
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            content(isExpanded)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.leading, 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .compositingGroup()
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(accent.opacity(0.1))
        }
    }

    @ViewBuilder
    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemSymbol: .chevronRight)
                    .font(.caption)
                    .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                Image(systemSymbol: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .shimmering(active: isShimmering)
                Spacer()
            }
            .foregroundStyle(accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
