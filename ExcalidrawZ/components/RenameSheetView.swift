//
//  RenameSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/2.
//

import SwiftUI

struct RenameSheetView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) var dismiss
    
    var onConfirm: (String) -> Void
    @State private var text: String = ""

    init(text: String = "", onConfirm: @escaping (String) -> Void) {
        self._text = State(initialValue: text)
        self.onConfirm = onConfirm
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack {
                content()
            }
            .padding()
        } else {
            Form {
                content()
            }
            .labelsHidden()
            .padding()
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Text(.localizable(.renameSheetHeadline))
            .font(.headline)
        
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)

        Divider()

        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(.localizable(.renameSheetButtonCancel))
                    .frame(width: 50)
            }
            Button {
                self.onConfirm(text)
                dismiss()
            } label: {
                Text(.localizable(.renameSheetButtonConfirm))
                    .frame(width: 50)
            }
            .disabled(text.isEmpty)
        }
    }
}

#Preview {
    RenameSheetView() { _ in
        
    }
}
