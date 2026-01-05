//
//  OptionButton.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI

/// A generic option button for selecting from predefined choices
/// Used for fill style, stroke style, sloppiness, edges, etc.
struct OptionButton: View {
    let label: AnyView
    let isSelected: Bool
    let action: () -> Void
    
    init<L: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> L,
    ) {
        self.isSelected = isSelected
        self.action = action
        self.label = AnyView(label())
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A horizontal group of option buttons
struct OptionButtonGroup<T: Hashable>: View {
    var options: [T]
    var selectedValue: T
    var onSelect: (T) -> Void
    var label: (T) -> AnyView
    
    init<L: View>(
        options: [T],
        selectedValue: T,
        onSelect: @escaping (T) -> Void,
        @ViewBuilder label: @escaping (T) -> L
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onSelect = onSelect
        self.label = {
            AnyView(label($0))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                OptionButton(
                    isSelected: selectedValue == option
                ) {
                    onSelect(option)
                } label: {
                    label(option)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var settings = UserDrawingSettings()
        
        var body: some View {
            ScrollView {
                DrawingSettingsPanel(settings: $settings) {
                    print("Settings changed: \(settings)")
                }
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
