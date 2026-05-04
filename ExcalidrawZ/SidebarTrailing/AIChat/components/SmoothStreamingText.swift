//
//  SmoothStreamingText.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import MarkdownUI

/// Markdown view tuned for LLM streaming output.
///
/// **Why mask-reveal instead of fading text content?**
///
/// `MarkdownUI` rebuilds its internal view tree on every content change. Wrapping
/// the assignment in `withAnimation(...)` doesn't actually tween the text — the
/// new layout snaps in. So all the "linear / easeInOut / contentTransition" tricks
/// that work on plain `Text` are decorative noise on `Markdown`. The user perceives
/// a hard cut every flush, no matter the duration.
///
/// Instead we let the markdown re-layout *immediately* on each flush, but trim what
/// the user actually *sees* with a `mask`. The mask is an animatable
/// `Rectangle().frame(height: revealHeight)` whose height linearly catches up to
/// the new measured content height. SwiftUI animates `Rectangle` size reliably,
/// so the visible edge slides downward smoothly while the underlying markdown is
/// already in its final state.
///
/// **Why a fade strip at the bottom?**
///
/// Sharp horizontal mask edges look mechanical. A short gradient strip at the
/// reveal edge gives an "ink bleeding in" feel — new lines aren't slammed in,
/// they materialize through a soft border.
///
/// **Pacing**
///
/// Per user feedback "I don't care about latency, only smoothness":
///   - Flusher batches text every ~1 s.
///   - Reveal animates each batch over ~0.9 s linear.
///   - Reveal duration is *just* under the flush interval — by the time one batch
///     finishes revealing, the next batch lands. Motion is continuous, gaps are
///     ≤ 100 ms.
struct SmoothStreamingText: View {
    let target: String
    /// When true, mask the bottom edge so newly revealed text bleeds in.
    /// When false, content is fully visible (committed message render).
    var isStreaming: Bool = false

    @StateObject private var flusher = StreamFlusher()
    @State private var revealHeight: CGFloat = .infinity
    @State private var didMount: Bool = false

    /// Reveal duration is *deliberately longer* than the flusher's batch interval
    /// (1.0 s). When the next batch lands at t=1.0 s, the previous reveal is still
    /// at ~83% — `withAnimation` interrupts and starts a fresh linear from the
    /// current animated value to the new measured height. Motion is continuous.
    /// If reveal == batch, animation finishes ~100 ms before the next one starts
    /// and you see the visible edge briefly stop, which reads as a stutter.
    private static let revealAnimation: Animation = .linear(duration: 1.2)
    private static let maskTransitionAnimation: Animation = .linear(duration: 0.4)
    private static let fadeStripHeight: CGFloat = 28

    var body: some View {
        Markdown(flusher.displayText)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: SmoothStreamHeightKey.self,
                            value: proxy.size.height
                        )
                }
            }
            .onPreferenceChange(SmoothStreamHeightKey.self) { newHeight in
                handleHeightChange(newHeight)
            }
            .mask { maskShape }
            .animation(Self.maskTransitionAnimation, value: isStreaming)
            .onAppear { flusher.bootstrap(target) }
            .onChange(of: target) { flusher.ingest($0) }
            .onDisappear { flusher.cancel() }
    }

    @ViewBuilder
    private var maskShape: some View {
        if isStreaming {
            VStack(spacing: 0) {
                Rectangle()
                    .frame(height: max(0, revealHeight - Self.fadeStripHeight))
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.fadeStripHeight)
                Color.clear
            }
        } else {
            Color.black
        }
    }

    private func handleHeightChange(_ newHeight: CGFloat) {
        if !didMount {
            // First render: snap to current size, no animation. Historical messages
            // (and the very first frame of a live message) shouldn't pop in.
            revealHeight = newHeight
            didMount = true
            return
        }
        if isStreaming {
            withAnimation(Self.revealAnimation) {
                revealHeight = newHeight
            }
        } else {
            // Static render — content updated outside of streaming (e.g. round
            // committed). Snap to final size.
            revealHeight = newHeight
        }
    }
}

private struct SmoothStreamHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Flusher

@MainActor
private final class StreamFlusher: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var latestTarget: String = ""
    private var flushTask: Task<Void, Never>?

    /// Batch interval. Generous on purpose — user explicitly preferred smoothness
    /// over latency. Each flush is followed by a ~0.9 s reveal animation, so this
    /// effectively gives "1 paragraph per second" pacing.
    private let flushDelayNanos: UInt64 = 1_000_000_000

    func bootstrap(_ target: String) {
        guard displayText.isEmpty, latestTarget.isEmpty else { return }
        displayText = target
        latestTarget = target
    }

    func ingest(_ target: String) {
        latestTarget = target

        // Divergence (conversation switch / regenerate): snap, no animation.
        if !target.hasPrefix(displayText) {
            flushTask?.cancel()
            flushTask = nil
            displayText = target
            return
        }

        // Already caught up.
        if target == displayText { return }

        // Schedule a flush. If one's already pending, leave it — guarantees a
        // hard ceiling of `flushDelayNanos` between visible updates without
        // thrashing on every character.
        guard flushTask == nil else { return }
        let delay = flushDelayNanos
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            self.flushTask = nil
            guard !Task.isCancelled else { return }
            // No `withAnimation` — `Markdown` doesn't tween content anyway, and
            // the visible reveal motion is owned by the mask animation downstream.
            if self.displayText != self.latestTarget {
                self.displayText = self.latestTarget
            }
        }
    }

    func cancel() {
        flushTask?.cancel()
        flushTask = nil
    }

    deinit {
        flushTask?.cancel()
    }
}
