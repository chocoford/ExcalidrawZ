//
//  LeadingChevronDisclosureGroupStyle.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/1/25.
//

import SwiftUI

private struct DisclosureGroupLabelAction: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private extension EnvironmentValues {
    var disclosureGroupLabelAction: (() -> Void)? {
        get { self[DisclosureGroupLabelAction.self] }
        set { self[DisclosureGroupLabelAction.self] = newValue }
    }
}

private struct EnableDisclosureGroupLabelActionKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private extension EnvironmentValues {
    var isDefaultLabelActionEnabled: Bool {
        get { self[EnableDisclosureGroupLabelActionKey.self] }
        set { self[EnableDisclosureGroupLabelActionKey.self] = newValue }
    }
}

extension View {
//    @MainActor @ViewBuilder
//    public func disclosureGroupLabelOnTap(action: @escaping () -> Void) -> some View {
//        environment(\.disclosureGroupLabelAction, action)
//    }
    
    @MainActor @ViewBuilder
    public func disableDisclosureLabelDefaultAction(
        _ disabled: Bool = true
    ) -> some View {
        environment(\.isDefaultLabelActionEnabled, !disabled)
    }
}


@available(macOS 13.0, *)
struct LeadingChevronDisclosureGroupStyle: DisclosureGroupStyle {
    @Environment(\.diclosureGroupDepth) private var depth
    @Environment(\.isDefaultLabelActionEnabled) private var isDefaultLabelActionEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Color.clear
                    .frame(width: CGFloat(depth * 8), height: 1)
                
                configuration.label
                    .lineLimit(1)
                    .truncationMode(.middle)
                    
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture()
                    .onEnded {
                        withAnimation {
                            configuration.isExpanded.toggle()
                        }
                    },
                isEnabled: isDefaultLabelActionEnabled
            )
            .overlay(alignment: .leading) {
                Image(systemSymbol: .chevronRight)
                    .font(.footnote)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            configuration.isExpanded.toggle()
                        }
                    }
            }
            
            if configuration.isExpanded {
                configuration.content
                    .disclosureGroupStyle(self)
                    .environment(\.diclosureGroupDepth, depth + 1)
            }
        }
    }
}

@available(macOS 13.0, *)
extension DisclosureGroupStyle where Self == LeadingChevronDisclosureGroupStyle {
    static var leadingChevron: LeadingChevronDisclosureGroupStyle { LeadingChevronDisclosureGroupStyle() }
}

