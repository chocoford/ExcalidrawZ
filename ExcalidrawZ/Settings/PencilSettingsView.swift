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
                Text(.localizable(.applePencilInterationModeOneFingerSelectTitle)).tag(ToolState.PencilInteractionMode.fingerSelect)
                Text(.localizable(.applePencilInterationModeOneFingerMoveTitle)).tag(ToolState.PencilInteractionMode.fingerMove)
            } label: {
                
            }
            .pickerStyle(.inline)
        } header: {
            Text(.localizable(.applePencilInterationTitle))
        } footer: {
            VStack(spacing: 10) {
                Text(.localizable(.applePencilInterationModeOneFingerSelectDescription))
                Text(.localizable(.applePencilInterationModeOneFingerMoveDescription))
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
                Text(.localizable(.applePencilConnectToPencil))
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
            Text(.localizable(.applePencilConnectionTips))
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
