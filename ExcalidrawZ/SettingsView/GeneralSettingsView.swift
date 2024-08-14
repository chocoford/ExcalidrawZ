//
//  GeneralSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if !APP_STORE
import Sparkle
#endif

struct GeneralSettingsView: View {
#if !APP_STORE
    @EnvironmentObject var updateChecker: UpdateChecker
#endif
    @EnvironmentObject var appPreference: AppPreference

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
            settingCellView("App appearacne") {
                HStack(spacing: 16) {
                    RadioGroup(selected: $appPreference.appearance) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
            settingCellView("Canvas appearance") {
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
                Text("Appearance")
            } else {
                Text("Appearance")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        
#if !APP_STORE
        Section {
            Toggle("Check updates automatically", isOn: $updateChecker.canCheckForUpdates)
        } header: {
            if #available(macOS 14.0, *) {
                Text("Update")
            } else {
                Text("Update")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Spacer()
                Button {
                    updateChecker.updater?.checkForUpdates()
                } label: {
                    Text("Check Updates")
                }
            }
        }
#endif
    }
    
    @ViewBuilder
    func settingCellView<T: View, V: View>(_ title: String,
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
//struct GeneralSettingsView_Previews: PreviewProvider {
//    static var previews: some View {
//        GeneralSettingsView()
//            .environmentObject(AppSettingsStore())
//            .environmentObject(UpdateChecker())
//    }
//}
#endif
