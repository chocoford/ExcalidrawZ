//
//  AboutView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/7.
//

import SwiftUI

import ChocofordUI

struct AboutView: View {
    var body: some View {
        if #available(macOS 13.0, *) {
            Form {
                content()
#if APP_STORE
                AboutChocofordView(isAppStore: true)
#else
                AboutChocofordView(isAppStore: false)
#endif
            }
            .formStyle(.grouped)
        } else {
            Form {
                content()
#if APP_STORE
                AboutChocofordView(isAppStore: true)
#else
                AboutChocofordView(isAppStore: false)
#endif
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
    
    @MainActor @ViewBuilder
    private func licenseView() -> some View {
        let license = """
MIT License

Copyright (c) 2020 Excalidraw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
        VStack {
            
        }
    }
}

#Preview {
    AboutView()
}
