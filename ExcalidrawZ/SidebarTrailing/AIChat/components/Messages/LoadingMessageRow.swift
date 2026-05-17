//
//  LoadingMessageRow.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI

/// Placeholder shown while an assistant turn is in flight but hasn't produced
/// any meaningful content yet. Three dots fade in sequentially to signal
/// "still working" without dominating the row.
struct LoadingMessageRow: View {
    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 6
    private let cycleDuration: Double = 1.0
    private let stagger: Double = 0.18

    var body: some View {
        TimelineView(.animation) { context in
            HStack(spacing: dotSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(dotOpacity(index: index, at: context.date))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2), in: Capsule())
        }
    }

    private func dotOpacity(index: Int, at date: Date) -> Double {
        let shiftedTime = date.timeIntervalSinceReferenceDate - stagger * Double(index)
        var phase = shiftedTime.truncatingRemainder(dividingBy: cycleDuration)
        if phase < 0 { phase += cycleDuration }
        let wave = (sin(phase / cycleDuration * .pi * 2 - .pi / 2) + 1) / 2
        return 0.25 + 0.75 * wave
    }
}

struct LoadingMessageSlot: View {
    let isVisible: Bool

    private static let collapseDuration = 0.22
    private static let defaultExpandedHeight: CGFloat = 44

    @State private var expansion: CGFloat
    @State private var measuredHeight: CGFloat = Self.defaultExpandedHeight
    @State private var isContentMounted: Bool
    @State private var unmountTask: Task<Void, Never>?

    init(isVisible: Bool) {
        self.isVisible = isVisible
        _expansion = State(initialValue: isVisible ? 1 : 0)
        _isContentMounted = State(initialValue: isVisible)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isContentMounted {
                LoadingMessageRow()
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(heightReader)
                    .opacity(Double(expansion))
                    .allowsHitTesting(isVisible)
                    .accessibilityHidden(!isVisible)
            }
        }
        .frame(height: measuredHeight * expansion, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onChange(of: isVisible) { visible in
            updateVisibility(visible)
        }
        .onDisappear {
            unmountTask?.cancel()
        }
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: LoadingMessageSlotHeightKey.self,
                value: proxy.size.height
            )
        }
        .onPreferenceChange(LoadingMessageSlotHeightKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            measuredHeight = ceil(height)
        }
    }

    private func updateVisibility(_ visible: Bool) {
        unmountTask?.cancel()
        if visible {
            isContentMounted = true
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeOut(duration: Self.collapseDuration)) {
                    expansion = 1
                }
            }
            return
        }

        withAnimation(.easeOut(duration: Self.collapseDuration)) {
            expansion = 0
        }
        unmountTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Self.collapseDuration * 1000)))
            guard !Task.isCancelled, !isVisible else { return }
            isContentMounted = false
        }
    }
}

private struct LoadingMessageSlotHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 16) {
        LoadingMessageRow()
        LoadingMessageSlot(isVisible: false)
            .border(.red)
    }
    .padding()
}
#endif
