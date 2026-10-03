//
//  SidebarRowModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/12/25.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawZSidebarRowModifier: ViewModifier {
    @Environment(\.sidebarHoverSuppressed) private var hoverSuppressed
    @Environment(\.sidebarHoverAnimationsEnabled) private var hoverAnimationsEnabled

    var isSelected: Bool
    var isMultiSelected: Bool
    var isPressed: Bool = false
    
    @State private var isHovered = false

    private var isActive: Bool {
        (!hoverSuppressed && isHovered) || isSelected || isPressed
    }

    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, iOS 26.0, *) {
            12
        } else {
            6
        }
    }

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
        .padding(6)
        .contentShape(Rectangle())
        .trackSidebarHover($isHovered)
        .background {
            rowBackground
                .animation(
                    hoverAnimationsEnabled && !hoverSuppressed ? .easeInOut(duration: 0.16) : nil,
                    value: isActive
                )
        }
        .padding(.vertical, {
            if #available(macOS 26.0, iOS 26.0, *) {
                1
            } else {
                0
            }
        }())
        .overlay {
            if isMultiSelected {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Capsule()
                        .stroke(Color.accentColor, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if isActive {
                let tint = isSelected
                    ? Color.accentColor.opacity(isPressed ? 0.26 : 0.18)
                    : Color.primary.opacity(isPressed ? 0.10 : 0.06)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular
                            .tint(tint)
                            .interactive(!hoverSuppressed),
                        in: Capsule()
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    isSelected
                    ? Color.accentColor.opacity(isPressed ? 0.28 : 0.2)
                    : Color.gray.opacity(isPressed ? 0.28 : 0.2)
                )
                .opacity(isActive ? 1 : 0)
        }
    }
}


struct ExcalidrawZSidebarRowButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isMultiSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ExcalidrawZSidebarRowModifier(
                isSelected: isSelected,
                isMultiSelected: isMultiSelected,
                isPressed: configuration.isPressed
            ))
    }
}
 
extension ButtonStyle where Self == ExcalidrawZSidebarRowButtonStyle {
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
