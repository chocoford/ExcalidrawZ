//
//  PencilSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//

import SwiftUI

struct PencilSettingsView: View {
    @EnvironmentObject var toolState: ToolState
    
    var body: some View {
        if #available(macOS 14.0, *) {
            Form {
                content()
            }
            .formStyle(.grouped)
        } else {
            ScrollView {
                VStack {
                    content()
                }
                .padding()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Section {
            Toggle(isOn: Binding {
                toolState.inPenMode
            } set: {
                if !$0 {
                    toolState.inPenMode = false
                }
            }) {
                Text("Connect to pencil")
            }
            .disabled(!toolState.inPenMode)
        } footer: {
            Text("You can activate pencil mode by tapping on the canvas with your Apple Pencil.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PencilSettingsView()
}
