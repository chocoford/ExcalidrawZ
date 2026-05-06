//
//  SmoothStreamingText.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI

import ChocofordUI
import MarkdownUI

struct SmoothStreamingText: View {
    let target: String
    var isStreaming: Bool = false
    
    @StateObject private var flusher = StreamFlusher()
    @State private var revealHeight: CGFloat = 0
    @State private var didMount: Bool = false
    
    @State private var localIsStreaming = true
    
    var body: some View {
        Markdown(flusher.displayText)
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
            .modifier(RevealHeightModifier(height: revealHeight))
            .animation(
                localIsStreaming ? .linear(duration: 1) : nil,
                value: revealHeight
            )
            .mask(maskShape)
            .onAppear {
                print("[DEBUG] onAppear target.count=\(target.count)")
                flusher.bootstrap(target)
            }
            .onChange(of: target) { newValue in
                print("[DEBUG] onChange target.count=\(newValue.count)")
                flusher.ingest(newValue)
            }
            .onChange(of: isStreaming, debounce: 1) { newValue in
                print("[DEBUG] isStreaming changed", isStreaming)
                localIsStreaming = newValue
            }
            .onAppear {
                if !isStreaming {
                    localIsStreaming = false
                }
            }
            .onDisappear {
                print("[DEBUG] onDisappear")
                flusher.cancel()
            }
    }
    
    @ViewBuilder
    private var maskShape: some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: isStreaming ? 24 : 0, alignment: .bottom)
            .animation(.smooth, value: isStreaming)
        }
    }
    
    private func handleHeightChange(_ newHeight: CGFloat) {
        guard newHeight > 0 else { return }
        // Hold off on reveal until content is tall enough that the
        // 24pt bottom-fade mask doesn't dominate the visible area.
        // Below 48pt (= 2× mask height) the first line itself sits
        // mostly inside the fade — the user sees a half-rendered
        // teaser ghost. Wait until there's a buffer of clear text
        // above the gradient before flipping `didMount`.
        guard newHeight >= 48 else { return }
        if !didMount {
            // First valid measurement: snap, no animation.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                revealHeight = newHeight
                didMount = true
            }
            return
        }
        guard newHeight > revealHeight || !isStreaming else { return }
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
    
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    
    func body(content: Content) -> some View {
        content
            .frame(
                maxHeight: max(0, height),
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
    
    private let flushDelayNanos: UInt64 = 500_000_000
    
    func bootstrap(_ target: String) {
        guard displayText.isEmpty, latestTarget.isEmpty else { return }
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
