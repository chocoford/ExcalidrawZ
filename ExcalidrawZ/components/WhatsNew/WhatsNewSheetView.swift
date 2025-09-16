//
//  WhatsNewSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/12/3.
//

import SwiftUI
import ChocofordUI
import AVKit

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
#if DEBUG
                isPresented = true
#endif
                if let buildString = Bundle.main.infoDictionary!["CFBundleVersion"] as? String,
                   lastBuild < (Int(buildString) ?? 0) {
                    isPresented = true
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func sheetContent() -> some View {
        WhatsNewView()
    }
}

struct WhatsNewView: View {
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    var showContinue: Bool
    init(showContinue: Bool = true) {
        self.showContinue = showContinue
    }
    
    @State var navigationSize: CGSize = .zero
    
    enum Route: Hashable {
        case allFeatures
        case video(URL)
    }

    @State var route: Route? = nil
    
    @State private var navigationMaxHeight: CGFloat = .zero
    
    var body: some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            NavigationStack {
                ZStack {
                    if containerHorizontalSizeClass == .compact {
                        navigationContent()
                    } else {
                        navigationContent()
                           
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                        case .allFeatures:
                            allFeaturesList()
                        case .video(let url):
                            VideoPlayer(player: AVPlayer(url: url))
                    }
                }
            }
#if os(macOS)
            .frame(width: 720, height: 500)
#endif
        } else {
            if route == nil {
                ZStack {
                    if containerHorizontalSizeClass == .compact {
                        navigationContent()
                    } else {
                        navigationContent()
                            .frame(width: 720)
                    }
                }
            } else if route == .allFeatures {
                allFeaturesList()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func navigationContent() -> some View {
        ScrollView {
            if containerHorizontalSizeClass == .compact {
                content()
            } else {
                content()
                    .padding(.horizontal, 40)
            }
        }
        .readSize($navigationSize)
//        .watchImmediately(of: navigationSize) { newValue in
//            navigationMaxHeight = max(navigationMaxHeight, newValue.height)
//        }
        .overlay(alignment: .topLeading) {
            ZStack {
                if #available(macOS 26.0, *) {
                    dismissButton()
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass)
                        .controlSize(.extraLarge)
                } else {
                    dismissButton()
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                }
            }
            .padding(20)
        }
//        .toolbar {
//#if os(macOS)
//            ToolbarItem(placement: .cancellationAction) {
//                if #available(macOS 13.0, iOS 16.0, *) {
//                    Text("") // <-- only with this, the continue button below will show (macOS)
//                } else {
//                    if showContinue {
//                        Button {
//                            dismiss()
//                        } label: {
//                            Text(.localizable(.whatsNewButtonContinue))
//                                .padding(.horizontal)
//                        }
//                        .buttonStyle(.borderedProminent)
//                    }
//                }
//            }
//#endif
//            ToolbarItem(placement: .primaryAction) {
//                if #available(macOS 13.0, iOS 16.0, *) {
//                    if showContinue {
//                        Button {
//                            dismiss()
//                        } label: {
//                            Text(.localizable(.whatsNewButtonContinue))
//                        }
//                    }
//                }
//            }
//        }
#if os(iOS)
        .navigationTitle(Text(.localizable(.whatsNewTitle)))
        .navigationBarTitleDisplayMode(.large)
#endif
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 0) {
#if os(macOS)
            VStack(spacing: 6) {
                Text(.localizable(.whatsNewTitle)).font(.largeTitle)
            }
#endif
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 22) {
                    Image("What's New Cover")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
#if os(macOS)
                        .padding(.horizontal, 80)
#endif
                    
                     featuresContent()
                }
                .padding(.vertical)
                .fixedSize(horizontal: false, vertical: true)
                
#if os(iOS)
                ViewThatFits {
                    HStack {
                        communityLinks()

                        Spacer()
                        NavigationLink(.localizable(.whatsNewButtonAllFeatures)) {
                            allFeaturesList()
                        }
                        .buttonStyle(.linkStyle)

                    }
                    
                    VStack {
                        HStack {
                            Spacer()
                            NavigationLink(.localizable(.whatsNewButtonAllFeatures)) {
                                allFeaturesList()
                            }
                            .buttonStyle(.linkStyle)
                        }
                        HStack {
                            communityLinks()
                        }
                    }
                }
#else
                HStack {
                    communityLinks()
                    
                    Spacer()
                    if #available(macOS 13.0, iOS 16.0, *) {
                        NavigationLink(value: Route.allFeatures) {
                            Text(.localizable(.whatsNewButtonAllFeatures))
                        }
                        .buttonStyle(.link)
                    } else {
                        Button {
                            route = .allFeatures
                        } label: {
                            Text(.localizable(.whatsNewButtonAllFeatures))
                        }
                        .buttonStyle(.link)
                    }
                }
#endif
            }
        }
#if os(macOS)
        .padding(.top, 40)
#endif
        .padding(.horizontal, containerHorizontalSizeClass == .compact ? 10 : 40)
        .padding(.bottom, 40)
    }
    
    @MainActor @ViewBuilder
    private func warnningSection() -> some View {
        VStack {
            Text(.localizable(.whatsNewWarningBody))
            
            HStack {
                Spacer(minLength: 0)
                
                communityLinks()
            }
        }
        .font(.callout)
        .padding()
        .fixedSize(horizontal: false, vertical: true)
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
    
    @MainActor @ViewBuilder
    private func communityLinks() -> some View {
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
                .foregroundStyle(.white)
            }
            
            Link(destination: URL(string: "https://discord.gg/aCv6w4HxDg")!) {
                HStack {
                    Image("discord-mark-white")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                    Text(.localizable(.generalButtonJoinDiscord))
                }
                .foregroundStyle(.white)
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
    
    @MainActor @ViewBuilder
    private func dismissButton() -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemSymbol: .xmark)
        }
        .keyboardShortcut("w", modifiers: .command)
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
            WhatsNewView()
        }
#if os(macOS)
        .frame(width: 600, height: 800)
#endif
    } else {
        NavigationView {
            WhatsNewView()
        }
#if os(macOS)
        .frame(width: 600, height: 800)
#endif
    }
}
