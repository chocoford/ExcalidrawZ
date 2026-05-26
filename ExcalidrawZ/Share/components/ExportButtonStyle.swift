//
//  ExportButtonStyle.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/16/25.
//

import SwiftUI
import ChocofordUI

struct ExportButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isHovered = false
    
    let size: CGFloat = 86
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .padding()
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        if #available(macOS 26.0, iOS 26.0, *) {
                            let roundedRectangle = RoundedRectangle(cornerRadius: 20)

                            roundedRectangle
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))

                            if isEnabled {
                                roundedRectangle
                                    .fill(.clear)
                                    .glassEffect(
                                        Glass.regular
                                            .tint(Color.accentColor.opacity(isHovered ? 0.14 : 0.08))
                                            .interactive(),
                                        in: roundedRectangle
                                    )

                                if isPressed {
                                    roundedRectangle
                                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                } else if isHovered {
                                    roundedRectangle
                                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                                }
                            } else {
                                roundedRectangle
                                    .fill(.clear)
                                    .glassEffect(
                                        Glass.clear,
                                        in: roundedRectangle
                                    )
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isEnabled ?
                                    (
                                        isPressed ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(isHovered ? .ultraThickMaterial : .regularMaterial)
                                    ) : AnyShapeStyle(Color.clear)
                                )
                            
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.separator, lineWidth: 0.5)
                        }
                    }
                    .animation(.default, value: isHovered)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
