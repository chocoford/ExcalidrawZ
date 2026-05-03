//
//  ExcalidrawSettingsView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/4/26.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawSettingsView: View {
    @EnvironmentObject private var appPreference: AppPreference
    @State private var editingSettings: UserDrawingSettings = UserDrawingSettings()

    var body: some View {
        if #available(macOS 14.0, *) {
            Form {
                content()
            }
            .formStyle(.grouped)
            .onAppear {
                loadSettings()
            }
        } else {
            ScrollView {
                VStack {
                    content()
                }
                .padding()
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private func loadSettings() {
        editingSettings = appPreference.customDrawingSettings
    }

    private func saveSettings() {
        appPreference.customDrawingSettings = editingSettings
    }
    
    @ViewBuilder
    private func content() -> some View {
        customDrawingSettingsSection()
    }
    
    @ViewBuilder
    private func customDrawingSettingsSection() -> some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Button {
                            NotificationCenter.default.post(.captureCurrentDrawingSettings())
                            Task {
                                loadSettings()

                                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.3))

                                loadSettings()

                                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))

                                loadSettings()
                            }
                        } label: {
                            Label(.localizable(.settingsExcalidrawButtonCaptureCurrentSettings), systemSymbol: .arrowDownCircle)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            editingSettings = UserDrawingSettings()
                            saveSettings()
                        } label: {
                            Label(.localizable(.generalButtonReset), systemSymbol: .arrowCounterclockwise)
                        }
                        .buttonStyle(.bordered)
                    }
                    .modernButtonStyle(style: .glass, shape: .modern)

                    DrawingSettingsPanel(
                        settings: $editingSettings,
                        onSettingsChange: saveSettings
                    )
                    .padding(.horizontal, 12)
                    .frame(width: 260, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text(localizable: .settingsExcalidrawDrawingSettingsTitle)
        } footer: {
            HStack {
                Spacer()
                Text("These defaults apply to new canvases. Override per canvas from the Preferences inspector.")
                    .foregroundStyle(.secondary)
            }
        }
    }

}

#Preview {
    ExcalidrawSettingsView()
        .environmentObject(AppPreference())
}
