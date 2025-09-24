//
//  SidebarRowModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/12/25.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawZSidebarRowModifier: ViewModifier {
    var isSelected: Bool
    var isMultiSelected: Bool
    
    @State private var isHovered = false
        
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
        .padding(6)
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation {
                self.isHovered = isHovered
            }
        }
        .background {
            let cornerRadius: CGFloat = {
                if #available(macOS 26.0, iOS 26.0, *) {
                    12
                } else {
                    4
                }
            }()
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .overlay {
            if isMultiSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isMultiSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            }
        }
    }
}


struct ExcalidrawZSidebarRowButtonStyle: PrimitiveButtonStyle {
    var isSelected: Bool
    var isMultiSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            configuration.label
                .modifier(ExcalidrawZSidebarRowModifier(
                    isSelected: isSelected,
                    isMultiSelected: isMultiSelected
                ))
        }
    }
}
 
extension PrimitiveButtonStyle where Self == ExcalidrawZSidebarRowButtonStyle {
    static func excalidrawSidebarRow(
        isSelected: Bool,
        isMultiSelected: Bool
    ) -> ExcalidrawZSidebarRowButtonStyle {
        ExcalidrawZSidebarRowButtonStyle(
            isSelected: isSelected,
            isMultiSelected: isMultiSelected
        )
    }
}

