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

#if DEBUG
#Preview {
    LoadingMessageRow()
        .padding()
}
#endif
