//
//  WhatsNewSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/12/3.
//

import SwiftUI

struct WhatsNewSheetViewModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @AppStorage("WhatsNewLastBuild") var lastBuild = 0
    
    @State private var isPresented = false
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleWhatsNewSheet)) { _ in
#if canImport(AppKit)
                if window == NSApp.keyWindow {
                    isPresented.toggle()
                }
#elseif canImport(UIKit)
                if let keyWindow = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) {
                    if keyWindow == window {
                        isPresented.toggle()
                    }
                }
#endif
            }
            .sheet(isPresented: $isPresented) {
                if let buildString = Bundle.main.infoDictionary!["CFBundleVersion"] as? String {
                    lastBuild = (Int(buildString) ?? 0)
                }
            } content: {
                sheetContent()
            }
            .bindWindow($window)
            .onAppear {
//#if DEBUG
//                isPresented = true
//#endif
                if let buildString = Bundle.main.infoDictionary!["CFBundleVersion"] as? String,
                   lastBuild < (Int(buildString) ?? 0) {
                    isPresented = true
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func sheetContent() -> some View {
        if containerHorizontalSizeClass == .compact {
            ScrollView {
                WhatsNewSheetView()
            }
        } else {
            WhatsNewSheetView()
                .padding(.horizontal, 60)
                .frame(width: 600)
        }
    }
}

struct WhatsNewSheetView: View {
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    var showContinue: Bool
    init(showContinue: Bool = true) {
        self.showContinue = showContinue
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(.localizable(.whatsNewTitle)).font(.largeTitle)
//                if let versionString = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String {
//                    Text(versionString).foregroundStyle(.secondary)
//                }
            }
            
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 22) {
                    Image("What's New Cover")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    fetureRow(
                        title: .localizable(.whatsNewItemMultiplatformTitle),
                        description: .localizable(.whatsNewItemMultiplatformDescription)
                    ) {
                        if #available(macOS 13.0, iOS 16.1, *) {
                            Image(systemSymbol: .macbookAndIphone)
                                .resizable()
                        } else {
                            Image(systemSymbol: .ipadAndIphone)
                                .resizable()
                        }
                    }
                    
                    fetureRow(
                        title: .localizable(.whatsNewItemPreventImageAutoInvertTitle),
                        description: .localizable(.whatsNewItemPreventImageAutoInvertDescription),
                        icon: Image(systemSymbol: .photoOnRectangle)
                    )
                    
                    
                    fetureRow(
                        title: .localizable(.whatsNewItemFileLoadPerformanceTitle),
                        description: .localizable(.whatsNewItemFileLoadPerformanceDescription),
                        icon: Image(systemSymbol: .timer)
                    )
                }
                .padding(.vertical)
                .fixedSize(horizontal: false, vertical: true)
                
                HStack {
                    Spacer()
                    Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ/blob/main/CHANGELOG.md")!) {
                        HStack(spacing: 2) {
                            Text("Change Log")
                            Image(systemSymbol: .arrowRight)
                        }
                    }
#if os(macOS)
                    .buttonStyle(.link)
#elseif os(iOS)
                    .buttonStyle(.linkStyle)
#endif
                }
            }
            
            warnningSection()
            
            if showContinue {
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.whatsNewButtonContinue))
                        .padding(.horizontal, 10)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }

    @MainActor @ViewBuilder
    private func fetureRow(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        icon: Image
    ) -> some View {
        fetureRow(
            title: title,
            description: description
        ) {
            icon
                .resizable()
        }
    }
    
    @MainActor @ViewBuilder
    private func fetureRow(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            icon()
                .symbolRenderingMode(.multicolor)
                .scaledToFit()
                .frame(width: 68, height: 40, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func warnningSection() -> some View {
        VStack {
            Text(.localizable(.whatsNewWarningBody))
            
            HStack {
                Spacer(minLength: 0)
                
                SwiftUI.Group {
                    Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ")!) {
                        HStack {
                            Image("github-mark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 16)
                            if containerHorizontalSizeClass == .compact {
                                Text("Github")
                            } else {
                                Text("Github repository")
                            }
                        }
                    }
                    
                    Link(destination: URL(string: "https://discord.gg/aCv6w4HxDg")!) {
                        HStack {
                            Image("discord-mark-white")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 16)
                            Text(.localizable(.generalButtonJoinDiscord))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background {
                    if #available(macOS 13.0, iOS 16.0, *) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    }
                }
            }
        }
        .font(.callout)
        .padding()
        .background {
            let roundRect = RoundedRectangle(cornerRadius: 12)
            ZStack {
                roundRect
                    .fill(
                        colorScheme == .dark ? Color(red: 43/255.0, green: 30/255.0, blue: 0) : Color(red: 1, green: 251.0/255.0, blue: 242.0/255.0)
                    )
                roundRect
                    .stroke(colorScheme == .dark ? Color(red: 1, green: 181/255.0, blue: 15/255.0) : Color(red: 158/255.0, green: 103/255.0, blue: 0))
            }
        }
    }
}

struct ChangeLogView: View {
    var body: some View {
        ScrollView {
            if let changeLogURL = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
               let changeLogText = try? String(contentsOf: changeLogURL, encoding: .utf8),
               let changeLog = try? AttributedString(
                markdown: changeLogText,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
               ) {
                Text(changeLog)
            }
        }
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, *) {
        NavigationStack {
            WhatsNewSheetView()
        }
        .frame(width: 600, height: 800)
    } else {
        NavigationView {
            WhatsNewSheetView()
        }
        .frame(width: 600, height: 800)
    }
}
