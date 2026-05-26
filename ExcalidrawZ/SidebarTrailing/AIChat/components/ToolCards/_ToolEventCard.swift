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
import ChocofordUI

struct ToolEventCard<Content: View, Trailing: View>: View {
    let icon: SFSymbol
    let title: String
    let accent: Color
    /// Pulsing shimmer on the title — used while a tool call is in flight
    /// so the user reads it as "busy" rather than "settled".
    var isShimmering: Bool = false
    /// When false the header remains visible but does not toggle the
    /// foldout. Used while raw tool-call arguments are still streaming:
    /// rendering a huge, changing JSON body is expensive and not useful.
    var isExpandable: Bool = true
    /// Replaces the chevron with an indeterminate spinner while the
    /// foldout is temporarily unavailable.
    var showsLoadingIndicator: Bool = false
    /// Right-aligned accessory in the header row, drawn after the
    /// `Spacer`. Used by `ToolCallCard` to show a "Denied" badge when
    /// the user rejected a tool's approval prompt; defaults to
    /// `EmptyView` so existing call sites keep working unchanged.
    @ViewBuilder var trailing: () -> Trailing
    /// Body builder. Receives the current expansion state so it can mix
    /// always-visible elements (images, summary) with collapse-on-fold
    /// elements (raw arguments, long text). Apply `.padding(.leading, 22)`
    /// inside the builder for the standard "indent under icon" alignment.
    @ViewBuilder var content: (_ isExpanded: Bool) -> Content

    @State private var isExpanded: Bool = false
    /// Natural height of `content(isExpanded)` as measured by the
    /// background `GeometryReader`. Drives the Animatable height
    /// modifier — same trick `CompactSummaryRow` uses to make
    /// SwiftUI's animation system propagate size changes through to
    /// `NSHostingView`'s `intrinsicContentSize`. Without this, a
    /// structural toggle (`if isExpanded { Text(...) }`) leaves
    /// AppKit autolayout with stale size info and the scroll view's
    /// `contentSize` lags — content overflows the viewport with no
    /// way to scroll to it.
    @State private var contentHeight: CGFloat = 0
    @State private var hasMeasuredContentHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bodyContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .compositingGroup()
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(accent.opacity(0.1))
        }
        .watch(value: isExpandable) { _, canExpand in
            guard !canExpand, isExpanded else { return }
            hasMeasuredContentHeight = true
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = false
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        bodyContentCore
            .readHeight($contentHeight)
            .modifier(ToolEventBodyHeightModifier(height: contentHeight))
            .animation(hasMeasuredContentHeight ? .smooth : nil, value: contentHeight)
            .watch(value: contentHeight) { _, newValue in
                guard newValue > 0, !hasMeasuredContentHeight else { return }
                hasMeasuredContentHeight = true
            }
            .clipped()
    }

    private var bodyContentCore: some View {
        ZStack(alignment: .top) {
            content(isExpandable && isExpanded)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.leading, 22)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, isExpanded ? 4 : 0)
    }

    @ViewBuilder
    private var header: some View {
        Button {
            guard isExpandable else { return }
            hasMeasuredContentHeight = true
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if showsLoadingIndicator {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                        .scaleEffect(0.55)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemSymbol: .chevronRight)
                        .font(.caption)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        .frame(width: 10, height: 10)
                }
                Image(systemSymbol: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .shimmering(active: isShimmering)
                Spacer()
                trailing()
            }
            .foregroundStyle(accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToolEventBodyHeightModifier: Animatable, ViewModifier {
    var animatableData: CGFloat

    init(height: CGFloat) {
        self.animatableData = height
    }

    func body(content: Content) -> some View {
        content.frame(height: animatableData, alignment: .top)
    }
}

// MARK: - Trailing-less convenience

extension ToolEventCard where Trailing == EmptyView {
    /// Convenience init for cards that don't need a trailing accessory —
    /// matches the original signature so existing call sites
    /// (`ToolResultCard`, the simpler `ToolCallCard` form) compile
    /// unchanged.
    init(
        icon: SFSymbol,
        title: String,
        accent: Color,
        isShimmering: Bool = false,
        isExpandable: Bool = true,
        showsLoadingIndicator: Bool = false,
        @ViewBuilder content: @escaping (_ isExpanded: Bool) -> Content
    ) {
        self.icon = icon
        self.title = title
        self.accent = accent
        self.isShimmering = isShimmering
        self.isExpandable = isExpandable
        self.showsLoadingIndicator = showsLoadingIndicator
        self.trailing = { EmptyView() }
        self.content = content
    }
}
