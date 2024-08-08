//
//  GeneralSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
import Sparkle

struct GeneralSettingsView: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var appPreference: AppPreference

    var body: some View {
        Form {
            Section {
                settingCellView("Appearacne") {
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
                Text("Appearance")
            }
            
            
            Section {
                Toggle("Check updates automatically", isOn: $updateChecker.canCheckForUpdates)
            } header: {
                Text("Update")
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
        }
        .formStyle(.grouped)
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
