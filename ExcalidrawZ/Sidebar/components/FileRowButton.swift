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
        isInTrash: Bool = false,
        isSelected: Bool,
        isMultiSelected: Bool,
        onTap: @escaping () -> Void,
        
    ) {
        self.isSelected = isSelected
        self.isMultiSelected = isMultiSelected
        self.label = AnyView(
            FileRowLabel(
                name: name,
                updatedAt: updatedAt ?? .distantPast,
                isInTrash: isInTrash
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
            .modifier(
                ExcalidrawZSidebarRowModifier(
                    isSelected: isSelected,
                    isMultiSelected: isMultiSelected
                )
            )
            .animation(.easeOut(duration: 0.1), value: isMultiSelected)
            .simultaneousGesture(
                TapGesture().onEnded {
                    onTap()
                }
            )
    }
}

