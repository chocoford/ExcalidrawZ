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
    @State private var isAnimating: Bool = false

    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 6
    private let cycleDuration: Double = 1.0
    private let stagger: Double = 0.18

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(isAnimating ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: cycleDuration / 2)
                            .repeatForever()
                            .delay(stagger * Double(index)),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { isAnimating = true }
    }
}

#if DEBUG
#Preview {
    LoadingMessageRow()
        .padding()
}
#endif
