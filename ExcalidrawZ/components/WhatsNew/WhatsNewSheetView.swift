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
    
    @State private var navigationSize: CGSize = .zero
    
    enum Route: Hashable {
        case allFeatures
        case video(URL)
    }

    @State private var route: Route? = nil
    
    var body: some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            NavigationStack {
                ZStack {
                    if containerHorizontalSizeClass == .compact {
                        navigationContent()
                    } else {
                        navigationContent()
                            .frame(width: 720)
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                        case .allFeatures:
                            allFeaturesList()
                        case .video(let url):
                            VideoPlayer(player: AVPlayer(url: url))
#if os(macOS)
                                .frame(width: 720, height: 500)
#endif
                    }
                }
            }
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
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .cancellationAction) {
                if #available(macOS 13.0, iOS 16.0, *) {
                    Text("") // <-- only with this, the continue button below will show (macOS)
                } else {
                    if showContinue {
                        Button {
                            dismiss()
                        } label: {
                            Text(.localizable(.whatsNewButtonContinue))
                                .padding(.horizontal)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
#endif
            ToolbarItem(placement: .primaryAction) {
                if #available(macOS 13.0, iOS 16.0, *) {
                    if showContinue {
                        Button {
                            dismiss()
                        } label: {
                            Text(.localizable(.whatsNewButtonContinue))
                        }
                    }
                }
            }
        }
#if os(iOS)
        .navigationTitle(Text(.localizable(.whatsNewTitle)))
        .navigationBarTitleDisplayMode(.large)
#endif
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear {
                    navigationSize = geometry.size
                }
            }
        }
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
    private func featuresContent() -> some View {
        WhatsNewFeatureRow(
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
        
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewSubgroupsSupportTitle),
            description: .localizable(.whatsNewSubgroupsSupportDescription)
        ) {
            Image(systemSymbol: .listBulletIndent)
                .resizable()
                .scaledToFit()
                .padding(.leading, 2)
        }
        
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewSupportLocalFoldersTitle),
            description: .localizable(.whatsNewSupportLocalFoldersDescription),
            icon: Image(systemSymbol: .folder)
        )
        
        
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewSupportMathTitle),
            description: .localizable(.whatsNewSupportMathDescription),
            icon: Image(systemSymbol: .xSquareroot)
        )
        
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewNewDrawFromClipboardTitle),
            description: .localizable(.whatsNewNewDrawFromClipboardDescription),
            icon: Image(systemSymbol: .docOnClipboard)
        )
 
        
#if os(iOS)
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewApplePencilToolbarTitle),
            description: .localizable(.whatsNewApplePencilToolbarDescrition),
            icon: Image(systemSymbol: .applepencilTip)
        )
       
        if UIDevice().userInterfaceIdiom == .pad {

        } else if UIDevice().userInterfaceIdiom == .phone {

        }
#endif
    }
    
    @MainActor @ViewBuilder
    private func allFeaturesList() -> some View {
        VStack {
            if #available(macOS 13.0, iOS 16.0, *) {} else {
                HStack {
                    Button {
                        route = nil
                    } label: {
                        Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(4)
                
                Divider()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            featuresContent()
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewFallbackExcalifontTitle),
                                description: .localizable(.whatsNewFallbackExcalifontDescription),
                                icon: Image(systemSymbol: .characterCursorIbeam)
                            ) {
                                if let url = Bundle.main.url(forResource: "Fallback Excalifont 720p", withExtension: "mov") {
                                    if #available(macOS 13.0, iOS 16.0, *) {
                                        NavigationLink(value: Route.video(url)) {
                                            WhatsNewRowMediaPreviewView(url: url)
                                        }
                                        .buttonStyle(.borderless)
                                    } else {
                                        Button {
                                            route = .video(url)
                                        } label: {
                                            WhatsNewRowMediaPreviewView(url: url)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewMoreToolsSupportTitle),
                                description: .localizable(.whatsNewMoreToolsSupportDescription)
                            ) {
                                if #available(macOS 15.0, iOS 18.0, *) {
                                    Image(systemName: "xmark.triangle.circle.square")
                                        .resizable()
                                } else {
                                    Image(systemSymbol: .shippingbox)
                                        .resizable()
                                }
                            }
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewLosslessPDFExportTitle),
                                description: .localizable(.whatsNewLosslessPDFExportDescription),
                                icon: Image(systemSymbol: .scribble)
                            )
                        } header: {
                            Text("v1.2.9")
                                .font(.headline)
                            Divider()
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewMoreI18nSupportTitle),
                                description: .localizable(.whatsNewMoreI18nSupportDescription),
                                icon: Image(systemSymbol: .docRichtext)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.8")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewMultiTouchTitle),
                                // 当使用两根手指触碰屏幕，将进行一次undo操作；当使用三根手指触碰屏幕，将进行一次redo操作
                                description: .localizable(.whatsnewMultiTouchDescription),
                                icon: Image(systemSymbol: .handTapFill)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewExportPDFTitle),
                                description: .localizable(.whatsnewExportPDFDescription),
                                icon: Image(systemSymbol: .docRichtext)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewExportImageWithoutBackgroundTitle),
                                description: .localizable(.whatsnewExportImageWithoutBackgroundDescription),
                                icon: Image(systemSymbol: .photoOnRectangle)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewApplePencilSupportTitle),
                                description: .localizable(.whatsnewApplePencilSupportDescription),
                                icon: Image(systemSymbol: .applepencil)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewAccesibleWithoutNetworkTitle),
                                description: .localizable(.whatsnewAccesibleWithoutNetworkDescription),
                                icon: Image(systemSymbol: .wifiSlash)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.7")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewItemPreventImageAutoInvertTitle),
                                description: .localizable(.whatsNewItemPreventImageAutoInvertDescription),
                                icon: Image(systemSymbol: .photoOnRectangle)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewItemFileLoadPerformanceTitle),
                                description: .localizable(.whatsNewItemFileLoadPerformanceDescription),
                                icon: Image(systemSymbol: .timer)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewIcloudSyncTitle),
                                description: .localizable(.whatsNewIcloudSyncDescription),
                                icon: Image(systemSymbol: .icloud)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.3")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
                .padding(.horizontal, containerHorizontalSizeClass == .compact ? 10 : 40)
            }
#if os(macOS)
            .frame(width: navigationSize.width, height: max(0, navigationSize.height - 40))
#endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ/blob/main/CHANGELOG.md")!) {
                    HStack(spacing: 2) {
                        Text("Change Log")
                        Image(systemSymbol: .arrowRight)
                    }
                }
            }
        }
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
}

struct WhatsNewRowMediaPreviewView: View {
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    @State private var mediaPreviewImage: Image?
    
    var body: some View {
        ZStack {
            if let mediaPreviewImage {
                mediaPreviewImage
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .frame(width: 120)
        .frame(maxHeight: 120)
        .overlay {
            Image(systemSymbol: .playCircleFill)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 60, maxHeight: 60)
                .padding(10)
                .blendMode(.difference)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onAppear {
            if let mediaURL = url {
                let asset = AVAsset(url: mediaURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                if #available(macOS 13.0,  *) {
                    imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, time, error in
                        Task.detached {
                            if let cgImage {
                                let image = Image(cgImage: cgImage)
                                await MainActor.run {
                                    self.mediaPreviewImage = image
                                }
                            }
                        }
                    }
                } else {
                    // Fallback on earlier versions
                }
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
