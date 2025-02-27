//
//  GeneralSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if os(macOS) && !APP_STORE
import Sparkle
#endif

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
#if os(macOS) && !APP_STORE
    @EnvironmentObject var updateChecker: UpdateChecker
#endif
    @EnvironmentObject var appPreference: AppPreference
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    @State private var isDisableBySettingsDialogPresented: Bool = false
    @State private var isRestartAlertPresented: Bool = false

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
            settingCellView(.localizable(.settingsAppAppearanceName)) {
                HStack(spacing: 16) {
                    RadioGroup(selected: $appPreference.appearance) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
            settingCellView(.localizable(.settingsExcalidrawAppearanceName)) {
                HStack(spacing: 16) {
                    RadioGroup(selected: $appPreference.excalidrawAppearance) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsAppAppearanceName))
            } else {
                Text(.localizable(.settingsAppAppearanceName))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
#if DEBUG
        Section {
            let containerShape = RoundedRectangle(cornerRadius: 8)
            HStack(alignment: .top, spacing: 20) {
                Text("Sidebar").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.sidebarLayout) { option, isOn in
                    Image(option.imageName("Sidebar"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                Text("Inspector").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.inspectorLayout) { option, isOn in
                    Image(option.imageName("Inspector"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
        } header: {
            Text("Layout")
        }
#endif
        
        Section {
            Toggle(.localizable(.settingsExcalidrawPreventImageAutoInvert), isOn: $appPreference.autoInvertImage)
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsExcalidraw))
            } else {
                Text(.localizable(.settingsExcalidraw))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
#if os(macOS) && !APP_STORE
        Section {
            Toggle(.localizable(.settingsUpdatesAutoCheckLabel), isOn: $updateChecker.canCheckForUpdates)
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsUpdateHeadline))
            } else {
                Text(.localizable(.settingsUpdateHeadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Spacer()
                Button {
                    updateChecker.updater?.checkForUpdates()
                } label: {
                    Text(.localizable(.settingsUpdatesButtonCheck))
                }
            }
        }
#endif
        
        Section {
            Toggle(.localizable(.settingsICloudToggleDisable), isOn: Binding {
                FileManager.default.ubiquityIdentityToken == nil ||
                isICloudDisabled
            } set: { disabled in
                isICloudDisabled = disabled
                if !disabled, FileManager.default.ubiquityIdentityToken == nil {
                    DispatchQueue.main.async {
                        isDisableBySettingsDialogPresented.toggle()
                    }
                }
            })
            .alert(
                .localizable(.settingsICloudDisableByAccountTitle),
                isPresented: $isDisableBySettingsDialogPresented
            ) {
                Button {
                    isDisableBySettingsDialogPresented.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isICloudDisabled.toggle()
                    }
                } label: {
                    Text(.localizable(.generalButtonOK))
                }
            } message: {
                Text(.localizable(.settingsICloudDisableByAccountMessage))
            }
            .alert(.localizable(.settingsICloudRestartToApplyMessage), isPresented: $isRestartAlertPresented) {
                Button {
#if canImport(AppKit)
                    NSApp.terminate(nil)
#elseif canImport(UIKit)
                    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    // terminaing app in background
                     DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                         exit(EXIT_SUCCESS)
                     })
#endif
                } label: {
                    Text(.localizable(.generalButtonCloseApp))
                }
            }
            .onChange(of: isICloudDisabled) { newValue in
                if newValue || FileManager.default.ubiquityIdentityToken != nil {
                    isRestartAlertPresented.toggle()
                }
            }
        } header: {
            Text(.localizable(.settingsICloudTitle))
        }
    }
    
    @MainActor @ViewBuilder
    func settingCellView<T: View, V: View>(_ title: LocalizedStringKey,
                                           @ViewBuilder trailing: @escaping () -> T,
                                           @ViewBuilder content: (() -> V) = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                trailing()
            }
            
            content()
        }
    }
}

#if DEBUG
#Preview {
    GeneralSettingsView()
        .environmentObject(AppPreference())
#if os(macOS) && !APP_STORE
        .environmentObject(UpdateChecker())
#endif
}
#endif
