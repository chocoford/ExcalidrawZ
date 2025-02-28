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
            Picker(selection: $toolState.pencilInteractionMode) {
                Text("Select with one finger").tag(ToolState.PencilInteractionMode.fingerSelect)
                Text("Move with one finger").tag(ToolState.PencilInteractionMode.fingerMove)
            } label: {
                
            }
            .pickerStyle(.inline)
        } header: {
            Text("Interaction")
        } footer: {
            VStack(spacing: 10) {
                Text("""
**Select with one finger**
    • Drag with one finger to select
    • Use two fingers to move or zoom the canvas
""")
                Text("""
**Move with one finger**
    • Use one finger to move the canvas
    • Use two fingers to move or zoom the canvas
    • Select with the dedicated tool
""")
            }
        }
        
        
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
            .onChange(of: toolState.inPenMode) { newValue in
                if !newValue {
                    Task {
                        try? await toolState.togglePenMode(enabled: false)
                    }
                }
            }
        } footer: {
            Text("You can activate pencil mode by tapping on the canvas with your Apple Pencil.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        NavigationStack {
            PencilSettingsView()
                .environmentObject(ToolState())
        }
    }
}
