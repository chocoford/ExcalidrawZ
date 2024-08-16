//
//  RenameSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/2.
//

import SwiftUI

struct RenameSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    var oldName: String
    var onConfirm: (String) -> Void
    @State private var text: String = ""

    init(text: String = "", onConfirm: @escaping (String) -> Void) {
        self.oldName = text
        self.onConfirm = onConfirm
        
    }

    var body: some View {
        Form {
            Text(.localizable(.renameSheetHeadline))
                .font(.headline)
            
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !text.isEmpty {
                        onConfirm(text)
                        dismiss()
                    }
                }
            
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
        .labelsHidden()
        .padding()
        .onAppear {
            self.text = self.oldName
        }
    }
}

#Preview {
    RenameSheetView() { _ in
        
    }
}
