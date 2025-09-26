//
//  ICloudSyncingView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/26/25.
//

import SwiftUI

struct ICloudSyncingView: View {
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    var isFirstImporting: Bool?
    
    @State private var isDisableICloudSyncingButtonPresented = false
    @State private var timer: Timer?
    
    var body: some View {
        ProgressView {
            VStack {
                if isFirstImporting == true {
                    Text(.localizable(.welcomeTitle)).font(.title)
                    Text(.localizable(.welcomeDescription))
                } else {
                    Text(.localizable(.welcomeSyncing))
                }
                
                if isDisableICloudSyncingButtonPresented {
                    Button {
                        isICloudDisabled = true
                    } label: {
                        Text(localizable: .settingsICloudToggleDisable)
                    }
                    .modernButtonStyle(style: .glass, shape: .capsule)
                    .padding(.top, 10)
                }
            }
            .modifier(ToggleICloudSyncingModifier())
        }
        .padding(40)
        .onAppear {
            self.timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
                self.isDisableICloudSyncingButtonPresented = true
            }
        }
        .onDisappear {
            self.timer?.invalidate()
        }
    }
}

#Preview {
    ICloudSyncingView()
}
