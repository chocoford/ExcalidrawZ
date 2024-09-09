//
//  AboutView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/7.
//

import SwiftUI

//import ChocofordUI

struct AboutView: View {
    var body: some View {
        if #available(macOS 13.0, *) {
            Form {
                content()
//                AboutChocofordView()
            }
            .formStyle(.grouped)
        } else {
            Form {
                content()
//                AboutChocofordView()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Section {
            HStack {
                Text(.localizable(.settingsAboutVersion))
                Spacer()
                Text(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text(.localizable(.settingsAboutBuild))
                Spacer()
                Text(Bundle.main.infoDictionary!["CFBundleVersion"] as! String)
                    .foregroundColor(.secondary)
            }
        } header: {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                    Text(Bundle.main.infoDictionary!["CFBundleDisplayName"] as! String)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom)
        } footer: {
            
        }
    }
    
    
//    @MainActor @ViewBuilder
//    private func abountChocoford() -> some View {
//        VStack {
//            
//        }
//    }
}

#Preview {
    AboutView()
}
