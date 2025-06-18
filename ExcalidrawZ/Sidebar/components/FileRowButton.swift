//
//  FileRowButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/26/25.
//

import SwiftUI

import ChocofordUI

struct FileRowButton: View {
    var isSelected: Bool
    var isMultiSelected: Bool
    var label: AnyView
    var onTap: () -> Void
    
    init(
        name: String,
        updatedAt: Date?,
        isSelected: Bool,
        isMultiSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        self.isSelected = isSelected
        self.isMultiSelected = isMultiSelected
        self.label = AnyView(
            FileRowLabel(
                name: name,
                updatedAt: updatedAt ?? .distantPast
            )
        )
        self.onTap = onTap
    }
    
    init<Label: View>(
        isSelected: Bool,
        isMultiSelected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isSelected = isSelected
        self.isMultiSelected = isMultiSelected
        self.label = AnyView(label())
        self.onTap = onTap
    }
    
    @State private var isHovered = false
    
    var body: some View {
        label
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { isHovered in
                withAnimation {
                    self.isHovered = isHovered
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                    .opacity(isHovered || isSelected ? 1 : 0)
            )
            .overlay {
                if isMultiSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isMultiSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                }
            }
            .animation(.easeOut(duration: 0.2), value: isMultiSelected)
            .simultaneousGesture(
                TapGesture().onEnded {
                    onTap()
                }
            )
    }
}
