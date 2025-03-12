//
//  RenameSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/2.
//

import SwiftUI

struct RenameSheetViewModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    
    @Binding var isPresented: Bool
    var name: String
    var callback: (_ newName: String) -> Void
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if #available(iOS 18.0, *), containerHorizontalSizeClass == .compact {
                    RenameSheetView(text: name) { newName in
                        callback(newName)
                    }
#if canImport(UIKit)
                    .presentationDetents([.height(140)])
                    .presentationDragIndicator(.visible)
                    .presentationCompactAdaptation(.sheet)
#endif
                } else if #available(iOS 18.0, macOS 13.0, *) {
                    RenameSheetView(text: name) { newName in
                        callback(newName)
                    }
                    .frame(width: 300, height: 140)
                    .scrollDisabled(true)
#if canImport(UIKit)
                    .presentationSizing(.fitted)
                    .presentationDragIndicator(.hidden)
                    .presentationCompactAdaptation(.sheet)
#endif
                } else {
                    RenameSheetView(text: name) { newName in
                        callback(newName)
                    }
#if canImport(UIKit)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(containerHorizontalSizeClass == .compact ? .visible : .hidden)
#elseif os(macOS)
                    .frame(width: 300)
#endif
                }
            }
    }
}

struct RenameSheetView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dismiss) var dismiss
    
    var onConfirm: (String) -> Void
    @State private var text: String = ""

    init(text: String = "", onConfirm: @escaping (String) -> Void) {
        self._text = State(initialValue: text)
        self.onConfirm = onConfirm
    }

    var body: some View {
//        if containerHorizontalSizeClass == .compact {
//            VStack {
//                content()
//            }
//            .padding()
//        } else {
            Form {
                content()
            }
#if os(macOS)
            .labelsHidden()
            .padding()
#endif
//        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Section {
            TextField("", text: $text)
                .submitLabel(.done)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !text.isEmpty {
                        onConfirm(text)
                        dismiss()
                    }
                }
#endif
        } header: {
            Text(.localizable(.renameSheetHeadline))
                .font(.headline)
        } footer: {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.renameSheetButtonCancel))
                        .frame(width: 64)
                }
                Button {
                    self.onConfirm(text)
                    dismiss()
                } label: {
                    Text(.localizable(.renameSheetButtonConfirm))
                        .frame(width: 64)
                }
                .disabled(text.isEmpty)
            }
        }
    }
}

#Preview {
    RenameSheetView() { _ in
        
    }
}
