//
//  SelectableDisclosureGroup.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/2/25.
//

import SwiftUI

import ChocofordUI

@available(macOS 13.0, *)
struct SelectableDisclosureGroup: View {
    @Environment(\.disclosureGroupExpandFlagKey) private var expandFlag
    @Environment(\.diclosureGroupDepth) private var depth
    @Environment(\.disclosureGroupIndicatorVisibility) private var indicatorVisibility

    @Binding var isSelected: Bool
    var content: AnyView
    var label: AnyView
    
    private let optionalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool = false

    var isExpanded: Binding<Bool> {
        optionalIsExpanded ?? $localIsExpanded
    }
    
    var config: Config = Config()

    init<Content: View, Label: View>(
        isSelected: Binding<Bool>,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._isSelected = isSelected
        self.optionalIsExpanded = isExpanded
        self.content = AnyView(content())
        self.label = AnyView(label())
    }

    init<Content: View, Label: View>(
        isSelected: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._isSelected = isSelected
        self.optionalIsExpanded = nil
        self.content = AnyView(content())
        self.label = AnyView(label())
    }
    
    @State private var expandSubGroupsFlag = false

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content
                .environment(\.diclosureGroupDepth, depth + 1)
                .environment(\.disclosureGroupExpandFlagKey, expandSubGroupsFlag)
        } label: {
            Button {
                isSelected = true
            } label: {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: CGFloat(depth * 8), height: 1)
                    
                    // Placeholder for chevron
                    Color.clear.frame(width: 8, height: 1)

                    Color.clear.frame(width: 4, height: 1)

                    label
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ListButtonStyle(selected: isSelected))
            .overlay(alignment: .leading) {
                if indicatorVisibility == .visible {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: CGFloat(depth * 8), height: 1)
                        
                        Image(systemSymbol: .chevronRight)
                            .font(.footnote)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .padding(4)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    let workItem = DispatchWorkItem(flags: .noQoS) {
                                        withAnimation(.smooth(duration: 0.2)) {
                                            isExpanded.wrappedValue.toggle()
                                        }
                                    }
#if canImport(AppKit)
                                    if NSEvent.modifierFlags.contains(.option) {
                                        expandSubGroupsFlag = !isExpanded.wrappedValue
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                                    } else {
                                        workItem.perform()
                                    }
#else
                                    workItem.perform()
#endif
                                },
                                including: .gesture
                            )
                    }
                }
            }
        }
        .disclosureGroupStyle(.selectable)
        .onAppear {
            expandSubGroupsFlag = expandFlag
            if expandFlag == true {
                withAnimation(.smooth(duration: 0.2)) {
                    isExpanded.wrappedValue = true
                }
            }
        }
        .onDisappear {
            expandSubGroupsFlag = false
        }
    }
}

@available(macOS 13.0, *)
extension SelectableDisclosureGroup {
    class Config {
        var isIndicatorVisibility: DisclosureGroupIndicatorVisibility = .visible
    }
    
//    public func diclosureGroupIndicatorVisibility(
//        _ visibility: DisclosureGroupIndicatorVisibility
//    ) -> Self {
//        self.config.isIndicatorVisibility = visibility
//        return self
//    }
}

@available(macOS 13.0, *)
struct SelectableDisclosureGroupStyle: DisclosureGroupStyle {
    @Environment(\.diclosureGroupDepth) private var depth
    
    @State private var localExpandFlag = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
            
            if configuration.isExpanded {
                configuration.content
                    .environment(\.disclosureGroupExpandFlagKey, localExpandFlag)
            }
        }
    }
}

@available(macOS 13.0, *)
extension DisclosureGroupStyle where Self == SelectableDisclosureGroupStyle {
    static var selectable: SelectableDisclosureGroupStyle {
        SelectableDisclosureGroupStyle()
    }
}

@available(macOS 13.0, *)
private struct SelectableDisclosureGroupPreviewView: View {
    @State private var isSelected = false
    
    var body: some View {
        SelectableDisclosureGroup(
            isSelected: $isSelected
        ) {
            Text("Content")
        } label: {
            Text("Label")
        }

    }
}
#Preview {
    if #available(macOS 13.0, *) {
        SelectableDisclosureGroupPreviewView()
    }
}
