//
//  OpacitySlider.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI

/// An opacity slider with min/max labels
struct OpacitySlider: View {
    @Binding var opacity: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingChanged: ((Bool) -> Void)?
    
    init(
        opacity: Binding<Double>,
        range: ClosedRange<Double> = 0...100,
        step: Double = 1,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._opacity = opacity
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: $opacity,
                in: range,
                // step: step,
                onEditingChanged: { editing in
                    onEditingChanged?(editing)
                }
            )
            .labelsHidden()
            
            HStack {
                Text("\(Int(range.lowerBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(range.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var opacity: Double = 75
        
        var body: some View {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opacity: \(Int(opacity))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    OpacitySlider(opacity: $opacity)
                }
                
                Rectangle()
                    .fill(Color.blue.opacity(opacity / 100))
                    .frame(height: 100)
                    .overlay(
                        Text("Preview")
                            .foregroundColor(.white)
                            .font(.title)
                    )
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
