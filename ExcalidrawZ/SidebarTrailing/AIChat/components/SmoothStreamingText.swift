//
//  SmoothStreamingText.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI

import ChocofordUI
import MarkdownUI

/// Markdown view tuned for LLM streaming output.
///
/// `MarkdownUI` rebuilds its internal view tree on every content change, so
/// wrapping the assignment in `withAnimation(...)` doesn't tween the text — the
/// new layout snaps in. Instead we let Markdown re-layout immediately at its
/// natural height, then constrain a custom `RevealHeightModifier` to a smaller
/// `revealHeight` that catches up via animation.
///
/// `fixedSize(vertical: true)` is load-bearing: it makes Markdown ignore the
/// parent's vertical proposal and lay out at its ideal height, so the background
/// `GeometryReader` can read the *natural* content height and feed it into
/// `revealHeight`.
///
/// On top of the frame+clip we apply a `mask` with a short gradient strip at
/// the bottom — purely visual, makes the reveal edge "ink in" instead of
/// looking like a guillotine cut.
///
/// **Anti-tease** is internalized: when streaming and the target hasn't
/// reached a minimum length yet, the view collapses to zero height.
/// Otherwise the user would see a single character pop in and stall
/// for ~700 ms while the next batch buffers — feels like the model froze. The
/// parent shows a loading row to cover this period; gate it on
/// `SmoothStreamingText.isMeaningfulLiveSnippet(_:)` to stay in lockstep.
struct SmoothStreamingText: View {
    let target: String
    /// When true, mask the bottom edge so newly revealed text bleeds in.
    /// When false, content is fully visible (committed message render).
    var isStreaming: Bool = false

    @StateObject private var flusher = StreamFlusher()
    @State private var revealHeight: CGFloat = 0
    @State private var didMount: Bool = false

    /// True iff the streaming snippet has accumulated enough to be worth
    /// showing. Used both internally (to collapse the view while streaming a
    /// tease) and externally (parent decides whether to show a loading row in
    /// this view's place).
    ///
    /// Length-only on purpose: an early `OK!` or `你好！` would pass any
    /// terminator-style heuristic but ships nothing of substance — the user
    /// just sees those 2-3 chars stall while the real content is still
    /// generating. Wait for the model to actually have something to say.
    static func isMeaningfulLiveSnippet(_ text: String) -> Bool {
        text.count >= 30
    }

    /// While streaming a too-short snippet, we collapse to zero height instead
    /// of rendering the partial text. Parent's loading row covers the gap.
    private var collapsed: Bool {
        isStreaming && !Self.isMeaningfulLiveSnippet(target)
    }

    var body: some View {
        // DEBUG: count body re-evals + log current target. If body re-evals on
        // every stream tick, target should change in the log; if it remounts
        // on every tick, you'll see ObjectIdentifier of `flusher` change.
        let _ = print(
            "[DEBUG] body flusher=\(ObjectIdentifier(flusher)) target.count=\(target.count) target.suffix=\(String(target.suffix(20)))"
        )
        return Markdown(flusher.displayText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .watch(value: proxy.size.height) { _, newValue in
                            handleHeightChange(newValue)
                        }
                }
            }
            .modifier(RevealHeightModifier(
                height: collapsed ? 0 : revealHeight,
                isActive: true
            ))
            .animation(.linear(duration: 0.5), value: revealHeight)
            .mask(maskShape)
            .onAppear {
                print("[DEBUG] onAppear target.count=\(target.count)")
                flusher.bootstrap(target)
            }
            .onChange(of: target) { newValue in
                print("[DEBUG] onChange target.count=\(newValue.count)")
                flusher.ingest(newValue)
            }
            .onDisappear {
                print("[DEBUG] onDisappear")
                flusher.cancel()
            }
    }

    /// Stable mask structure: always a VStack with rectangle + bottom gradient.
    /// We just collapse the gradient height to 0 when fade isn't wanted, so the
    /// view tree never restructures (which would unmount/remount the content
    /// and produce a show/hide/show flicker on first appear).
    @ViewBuilder
    private var maskShape: some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: (isStreaming && didMount) ? 24 : 0)
            .animation(.smooth, value: isStreaming && didMount)
        }
    }

    private func handleHeightChange(_ newHeight: CGFloat) {
        guard newHeight > 0 else { return }
        if !didMount {
            // First measurement: snap, no animation.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                revealHeight = newHeight
                didMount = true
            }
            return
        }
        guard newHeight > revealHeight else { return }
        revealHeight = newHeight
    }
}

// MARK: - Animatable height-revealer

/// Frame-clip pair driven by a custom `animatableData`. SwiftUI is forced to
/// interpolate `animatableData` during a transaction, calling `body(content:)`
/// at every animation frame with the intermediate height — more reliable than
/// `.frame(height:).animation(_:value:)` which silently drops tweens in some
/// preference-callback flows.
///
/// **Stable view structure**: `body(content:)` always returns the same shape
/// (`content.frame(maxHeight:).clipped()`); when not active we just feed
/// `.infinity` so the frame imposes no real constraint. This avoids the
/// unmount/remount flicker we'd get from an `if isActive` branch flip.
private struct RevealHeightModifier: ViewModifier, Animatable {
    var height: CGFloat
    var isActive: Bool

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(
                maxHeight: isActive ? max(0, height) : .infinity,
                alignment: .top
            )
            .clipped()
    }
}

// MARK: - Flusher

@MainActor
private final class StreamFlusher: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var latestTarget: String = ""
    private var flushTask: Task<Void, Never>?

    /// Batch interval. Caps Markdown re-render frequency. Each flush is followed
    /// by a ~0.5 s reveal animation; total visible-latency per batch is ~1.2 s.
    private let flushDelayNanos: UInt64 = 500_000_000

    func bootstrap(_ target: String) {
        guard displayText.isEmpty, latestTarget.isEmpty else { return }
        print("[DEBUG] bootstrap", target)
        displayText = target
        latestTarget = target
    }

    func ingest(_ target: String) {
        latestTarget = target
        print("[DEBUG] ingest", target)
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
