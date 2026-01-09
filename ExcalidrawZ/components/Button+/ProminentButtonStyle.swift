//
//  ProminentButtonStyle.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/12/25.
//

import SwiftUI

struct ProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    @MainActor @ViewBuilder
    func prominentButtonStyle() -> some View {
        modifier(ProminentButtonModifier())
    }
}

struct ModernButtonStyleModifier: ViewModifier {
    
    enum Size {
        case small, regular, large, extraLarge
    }
    
    enum BorderShape {
        case capsule, roundedRectangle(CGFloat?), circle
        /// Capsule in iOS 26, RoundedRectangle before iOS 26
        case modern
        case modernCircle
    }
    
    enum Style {
        case automatic, bordered, borderedProminent, plain, borderless
        case glass, glassProminent
    }
    
    var style: Style?
    var size: Size?
    var shape: BorderShape?
    
    var controlSize: ControlSize? {
        switch size {
            case .small:
                return .small
            case .regular:
                return .regular
            case .large:
                return .large
            case .extraLarge:
                if #available(macOS 14.0, iOS 17.0, *) {
                    return .extraLarge
                } else {
                    return .large
                }
            default:
                return nil
        }
    }
    
    var buttonBorderShape: ButtonBorderShape? {
        if #available(macOS 14.0, iOS 17.0, *) {
            switch shape {
                case .capsule:
                    return .capsule
                case .roundedRectangle(let radius?):
                    return .roundedRectangle(radius: radius)
                case .roundedRectangle(nil):
                    return .roundedRectangle
                case .circle:
                    return .circle
                case .modern:
                    if #available(macOS 26.0, iOS 26.0, *) {
                        return .capsule
                    } else {
                        return .roundedRectangle
                    }
                case .modernCircle:
                    if #available(macOS 26.0, iOS 26.0, *) {
                        return .circle
                    } else {
                        return .roundedRectangle
                    }
                default:
                    return nil
            }
        } else {
            return nil
        }
       
    }
    
    func body(content: Content) -> some View {
        ZStack {
            switch style {
                case .automatic:
                    content.buttonStyle(.automatic)
                case .bordered:
                    content.buttonStyle(.bordered)
                case .borderedProminent:
                    content.buttonStyle(.borderedProminent)
                case .borderless:
                    content.buttonStyle(.borderless)
                case .plain:
                    content.buttonStyle(.plain)
                case .glass:
                    if #available(macOS 26.0, iOS 26.0, *) {
                        content.buttonStyle(.glass)
                    } else {
                        content.buttonStyle(.bordered)
                    }
                case .glassProminent:
                    if #available(macOS 26.0, iOS 26.0, *) {
                        content.buttonStyle(.glassProminent)
                    } else {
                        content.buttonStyle(.borderedProminent)
                    }
                default:
                    content
            }
        }
        .apply { content in
            if let controlSize {
                content.controlSize(controlSize)
            } else {
                content
            }
        }
        .apply { content in
            if let buttonBorderShape {
                content.buttonBorderShape(buttonBorderShape)
            } else {
                content
            }
        }
    }
}


extension View {
    @MainActor @ViewBuilder
    func modernButtonStyle(
        style: ModernButtonStyleModifier.Style? = nil,
        size: ModernButtonStyleModifier.Size? = nil,
        shape: ModernButtonStyleModifier.BorderShape? = nil,
    ) -> some View {
        modifier(
            ModernButtonStyleModifier(
                style: style,
                size: size,
                shape: shape,
            )
        )
    }
}
