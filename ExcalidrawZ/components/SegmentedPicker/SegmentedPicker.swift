//
//  SegmentedPicker.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import Observation
import SwiftUI
import ChocofordUI

@Observable
class SegmentedPickerModel<Selection> where Selection : Hashable {
    private(set) var selection: Selection?

    var onSelectionChanged: ((Selection?) -> Void)?

    func setSelection(_ newValue: Selection?) {
        guard selection != newValue else { return }
        selection = newValue
        onSelectionChanged?(newValue)
    }

    func syncSelection(_ newValue: Selection?) {
        guard selection != newValue else { return }
        selection = newValue
    }
}

struct SegmentedPicker<Selection, Content>: View where Selection : Hashable, Content : View {
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var selection: Selection?
    var content: () -> Content
    
    init(
        selection: Binding<Selection?>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._selection = selection
        self.content = content
    }
    
    @State private var viewModel = SegmentedPickerModel<Selection>()
    @State private var canAnimateSelectionBackground = false
    
    var body: some View {
        _VariadicView.Tree(SegmentedPickerContent()) {
            content()
        }
        .backgroundPreferenceValue(
            SegmentedPickerPreferenceKey.self,
            alignment: .center
        ) { value in
            if let selection = viewModel.selection, let anchor = value[selection.hashValue] {
                GeometryReader { geomerty in
                    let rect = geomerty[anchor]
                    SwiftUI.Group {
                        if #available(macOS 26.0, iOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    colorScheme == .dark
                                    ? AnyShapeStyle(Color.clear)
                                    : AnyShapeStyle(Material.ultraThickMaterial)
                                )
                                .glassEffect(
                                    .clear,
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
                    .animation(canAnimateSelectionBackground ? .bouncy : nil, value: rect)
                    .task {
                        guard !canAnimateSelectionBackground else { return }
                        await Task.yield()
                        canAnimateSelectionBackground = true
                    }
                }
            }
        }
        .environment(viewModel)
        .apply { content in
            if #available(iOS 17.0, macOS 14.0, *) {
                content
                    .onAppear {
                        bindViewModelSelection()
                    }
                    .watch(value: selection, initial: true) { _, newValue in
                        if newValue != viewModel.selection {
                            viewModel.syncSelection(newValue)
                        }
                    }
            } else {
                content
                    .onAppear {
                        bindViewModelSelection()
                    }
                    .watch(value: selection) { newValue in
                        if newValue != viewModel.selection {
                            viewModel.syncSelection(newValue)
                        }
                    }
            }
        }
    }

    private func bindViewModelSelection() {
        let selectionBinding = $selection
        viewModel.onSelectionChanged = { newValue in
            guard selectionBinding.wrappedValue != newValue else { return }
            selectionBinding.wrappedValue = newValue
        }
        viewModel.syncSelection(selectionBinding.wrappedValue)
    }
}


fileprivate struct SegmentedPickerContent: _VariadicView_MultiViewRoot {
    @State private var height: CGFloat = .zero
    
    @ViewBuilder
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
    @Environment(SegmentedPickerModel<Value>.self) var viewModel
    
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
    
    
    @ViewBuilder
    private func buttonView() -> some View {
        Button {
            viewModel.setSelection(value)
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
