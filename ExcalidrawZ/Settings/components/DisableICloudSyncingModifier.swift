//
//  DisableICloudSyncingModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/26/25.
//

import SwiftUI

struct ToggleICloudSyncingModifier: ViewModifier {
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false

    @State private var isRestartAlertPresented: Bool = false
    @State private var isDisableBySettingsDialogPresented: Bool = false

    func body(content: Content) -> some View {
        content
            .alert(
                String(localizable: .settingsICloudRestartToApplyMessage),
                isPresented: $isRestartAlertPresented
            ) {
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
            .alert(
                String(localizable: .settingsICloudDisableByAccountTitle),
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
            .onChange(of: isICloudDisabled) { newValue in
                if newValue || FileManager.default.ubiquityIdentityToken != nil {
                    isRestartAlertPresented.toggle()
                } else if !newValue,
                          FileManager.default.ubiquityIdentityToken == nil {
                    DispatchQueue.main.async {
                        isDisableBySettingsDialogPresented.toggle()
                    }
                }
            }
    }
}

struct EnableICloudSyncingModifier: ViewModifier {
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    @State private var isDisableBySettingsDialogPresented: Bool = false

    func body(content: Content) -> some View {
        content
            .alert(
                String(localizable: .settingsICloudDisableByAccountTitle),
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
            .onChange(of: isICloudDisabled) { newValue in
                if !newValue,
                   FileManager.default.ubiquityIdentityToken == nil {
                    DispatchQueue.main.async {
                        isDisableBySettingsDialogPresented.toggle()
                    }
                }
            }
    }
    
}

