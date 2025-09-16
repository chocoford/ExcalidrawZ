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
            AnyView(
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            content()
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.gray.opacity(0.7))
                        }
#if APP_STORE
                        AboutChocofordView(isAppStore: true)
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.gray.opacity(0.7))
                            }
#else
                        AboutChocofordView(isAppStore: false)
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.gray.opacity(0.7))
                            }
#endif
                    }
                    .padding()
                }
            )
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
                WithAsyncValue(isChinaAppStore) { isChina, error in
                    if isChina == true {
                        HStack {
                            Spacer()
                            Link(destination: URL(string: "https://beian.miit.gov.cn/")!) {
                                Text("粤ICP备2023139330号-5A")
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Image("AppIcon-macOS")
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
            HStack {
                Spacer()
                if let privacyPolicy = URL(string: "https://excalidrawz.chocoford.com/privacy/") {
                    Link(.localizable(.generalButtonPrivacyPolicy), destination: privacyPolicy)
                        .hoverCursor(.link)
                }
                Text("·")
                if let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                    Link(.localizable(.generalButtonTermsOfUse), destination: termsOfUse)
                        .hoverCursor(.link)
                }
                
            }
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
            Text(license)
        }
    }
}

#Preview {
    AboutView()
}

