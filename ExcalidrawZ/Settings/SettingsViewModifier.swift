//
//  SettingsViewModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/29/25.
//

import SwiftUI
import ChocofordUI

struct SettingsViewButton: View {
    @State private var isSettingsPresented = false
    
    var body: some View {
        ZStack {
#if os(macOS)
            if #available(macOS 26.0, iOS 26.0, *) {
                SettingsLink().labelStyle(.iconOnly)
            } else {
                SettingsButton(useDefaultLabel: true) {
                    Label(.localizable(.settingsName), systemSymbol: .gear)
                        .labelStyle(.iconOnly)
                }
            }
#elseif os(iOS)
            Button {
                isSettingsPresented.toggle()
            } label: {
                Label(.localizable(.settingsName), systemSymbol: .gear)
            }
#endif
        }
        .sheet(isPresented: $isSettingsPresented) {
            if #available(macOS 13.3, iOS 16.4, *) {
                SettingsView()
                    .presentationContentInteraction(.scrolls)
                    .swiftyAlert()
            } else {
                SettingsView()
                    .swiftyAlert()
            }
        }
    }
}

struct SettingsSheetPresentationModifier: ViewModifier {
#if os(iOS)
    @ObservedObject private var router = SettingsRouter.shared
    @State private var isSettingsPresented = false
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .watch(value: router.iOSSettingsPresentationRequestID) { requestID in
                guard requestID > 0 else { return }
                isSettingsPresented = true
            }
            .sheet(isPresented: $isSettingsPresented) {
                settingsSheetContent
            }
#else
        content
#endif
    }

#if os(iOS)
    @ViewBuilder
    private var settingsSheetContent: some View {
        if #available(iOS 16.4, *) {
            SettingsView()
                .presentationContentInteraction(.scrolls)
                .swiftyAlert()
        } else {
            SettingsView()
                .swiftyAlert()
        }
    }
#endif
}
