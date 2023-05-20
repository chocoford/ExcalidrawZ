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

    @EnvironmentObject var appSettings: AppSettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingCellView("Appearacne") {
                    HStack(spacing: 16) {
                        RadioGroup(selected: $appSettings.appearance) { option, isOn in
                            RadioButton(isOn: isOn) {
                                Text(option.text)
                            }
                        }
                    }
                }
                
                settingCellView("Update") {
                    Button {
                        updateChecker.updater?.checkForUpdates()
                    } label: {
                        Text("Check Updates")
                    }
                } content: {
                    Toggle("Check updates automatically", isOn: $updateChecker.canCheckForUpdates)
                }
            }
            .padding()
        }
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
struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
            .environmentObject(AppSettingsStore())
            .environmentObject(UpdateChecker())
    }
}
#endif
