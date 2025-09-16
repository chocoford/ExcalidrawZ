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
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isEnabled ?
                                    (
                                        isPressed ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(isHovered ? .ultraThickMaterial : .regularMaterial)
                                    ) : AnyShapeStyle(Color.clear)
                                )
                                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isEnabled ?
                                    (
                                        isPressed ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(isHovered ? .ultraThickMaterial : .regularMaterial)
                                    ) : AnyShapeStyle(Color.clear)
                                )
                            
                            if #available(macOS 13.0, iOS 17.0, *) {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.separator, lineWidth: 0.5)
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.gray, lineWidth: 0.5)
                            }
                        }
                        
                       
                    }
                    .animation(.default, value: isHovered)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
