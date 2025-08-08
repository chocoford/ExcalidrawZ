//
//  SegmentedPicker.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI
import ChocofordUI

class SegmentedPickerModel<Selection>: ObservableObject where Selection : Hashable {
    @Published var selection: Selection?
}

struct SegmentedPicker<Selection, Content>: View where Selection : Hashable, Content : View {
    
    @Binding var selection: Selection?
    var content: () -> Content
    
    init(
        selection: Binding<Selection?>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._selection = selection
        self.content = content
    }
    
    @StateObject private var viewModel = SegmentedPickerModel<Selection>()
    
    var body: some View {
        _VariadicView.Tree(SegmentedPickerContent()) {
            content()
        }
        .backgroundPreferenceValue(
            SegmentedPickerPreferenceKey.self,
            alignment: .center
        ) { value in
            if let selection, let anchor = value[selection.hashValue] {
                GeometryReader { geomerty in
                    let rect = geomerty[anchor]
                    SwiftUI.Group {
                        if #available(macOS 26.0, iOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 10)
                                .glassEffect(
                                    .regular,
                                    in: .rect(cornerRadius: 10)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.background)
                                .shadow(radius: 1, y: 2)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(.bouncy, value: rect)
                }
            }
        }
        .environmentObject(viewModel)
        .apply { content in
            if #available(iOS 17.0, macOS 14.0, *) {
                content
                    .onChange(of: selection) { oldValue, newValue in
                        if newValue != viewModel.selection {
                            viewModel.selection = newValue
                        }
                    }
                    .onChange(of: viewModel.selection, initial: true) { oldValue, newValue in
                        if newValue != selection {
                            selection = newValue
                        }
                    }
            } else {
                content
                    .onChange(of: selection) { newValue in
                        if newValue != viewModel.selection {
                            viewModel.selection = newValue
                        }
                    }
                    .watchImmediately(of: viewModel.selection) { newValue in
                        if newValue != selection {
                            selection = newValue
                        }
                    }
            }
        }
    }
}


fileprivate struct SegmentedPickerContent: _VariadicView_MultiViewRoot {
    @State private var height: CGFloat = .zero
    
    @MainActor @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        HStack {
            ForEach(children) { child in
                child
                if child.id != lastID {
                    Divider()
                        .frame(height: height == 0 ? 10 : height)
                }
            }
        }
        .readHeight($height)
    }
}


struct SegmentedPickerItem<Value>: View where Value : Hashable {
    @EnvironmentObject var viewModel: SegmentedPickerModel<Value>
    
    var value: Value
    var content: AnyView
    
    init<Content : View>(
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.value = value
        self.content = AnyView(content())
    }
    
    var isSelected: Bool { value == viewModel.selection }
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            buttonView()
                .buttonStyle(
                    .text(
                        size: .xsmall,
                        square: true,
                        shape: .roundedRectangle(cornerRadius: 10)
                    )
                )
        } else {
            buttonView()
                .buttonStyle(.borderless)
        }
    }
    
    
    @MainActor @ViewBuilder
    private func buttonView() -> some View {
        Button {
            viewModel.selection = value
        } label: {
            content
                .foregroundStyle(
                    isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(HierarchicalShapeStyle.primary)
                )
                .background {
                    Color.clear
                        .anchorPreference(
                            key: SegmentedPickerPreferenceKey.self,
                            value: .bounds
                        ) {
                            [value.hashValue : $0]
                        }
                }
        }
    }
}


#if DEBUG
internal struct SegmentedPickerView: View {
    @State private var selection: Int? = 0
    
    var body: some View {
        SegmentedPicker(selection: $selection) {
            SegmentedPickerItem(value: 1) {
                Text("1")
                .frame(width: 26, height: 26)
                .padding(4)
//                .background {
//                    RoundedRectangle(cornerRadius: 6)
//                        .fill(Color.accentColor.opacity(0.3))
//                }
            }
            SegmentedPickerItem(value: 2) {
                Text("2")
                .frame(width: 26, height: 26)
                .padding(4)
            }
        }
        .background {
            if #available(macOS 14.0, iOS 17.0, *) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .stroke(.separator, lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            }
        }
        .padding()
    }
}

#Preview {
    SegmentedPickerView()
}
#endif
