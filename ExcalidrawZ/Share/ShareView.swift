//
//  ShareView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/7.
//

import SwiftUI
import WebKit

import ChocofordUI
import SwiftyAlert
import SFSafeSymbols

struct ShareViewModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var sharedFile: File?
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $sharedFile) { file in
                if horizontalSizeClass == .compact {
                    self.content(file)
#if os(iOS)
                        .presentationDetents([.fraction(0.4)])
                        .presentationDragIndicator(.visible)
#endif
                } else {
                    self.content(file)
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content(_ file: File) -> some View {
        ZStack {
            if #available(macOS 13.0, iOS 16.0, *) {
                ShareView(sharedFile: file)
                    .swiftyAlert()
            } else {
                ShareViewLagacy(sharedFile: file)
                    .swiftyAlert()
            }
        }
#if os(macOS)
        .frame(height: 300)
#endif
        
    }
}


@available(macOS 13.0, iOS 16.0, *)
struct ShareView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass

    @Environment(\.dismiss) var dismiss
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var exportState: ExportState

    
    var sharedFile: File
    
    init(sharedFile: File) {
        self.sharedFile = sharedFile
    }
    
    enum Route: Hashable {
        case exportImage
        case exportFile
#if DEBUG
        case svgPreview(URL)
#endif
    }
    
    @State private var route: NavigationPath = .init()
    
    
#if os(iOS)
    @State private var exportedPDFURL: URL?
#endif
    
    var body: some View {
        NavigationStack(path: $route) {
            VStack(spacing: horizontalSizeClass == .compact ? 10 : 20) {
                Text(.localizable(.exportSheetHeadline))
                    .font(horizontalSizeClass == .compact ? .headline : .largeTitle)
                
                HStack(spacing: 14) {
                    SquareButton(title: .localizable(.exportSheetButtonImage), icon: .photo) {
                        route.append(Route.exportImage)
                    }
                    .disabled((try? ExcalidrawFile(from: sharedFile).elements.isEmpty) != false)
                    
                    SquareButton(title: .localizable(.exportSheetButtonFile), icon: .doc) {
                        route.append(Route.exportFile)
                    }
                    
                    SquareButton(title: .localizable(.exportSheetButtonPDF), icon: .docRichtext, priority: .background) {
                        do {
                            let imageData = try await exportState.exportCurrentFileToImage(
                                type: .svg,
                                embedScene: false,
                                withBackground: true
                            )
#if os(macOS)
                            await exportPDF(name: imageData.name, svgURL: imageData.url)
#elseif os(iOS)
                            exportedPDFURL = await exportPDF(name: imageData.name, svgURL: imageData.url)
//                            route.append(Route.svgPreview(imageData.url))
#endif
                        } catch {
                            alertToast(error)
                        }
                    }
#if os(iOS)
                    .activitySheet(item: $exportedPDFURL)
#endif
                    
#if os(macOS)
                    SquareButton(title: .localizable(.exportSheetButtonArchive), icon: .archivebox) {
                        do {
                            try archiveAllFiles()
                        } catch {
                            alertToast(error)
                        }
                    }
#endif

                }

                if horizontalSizeClass != .compact {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(.localizable(.exportSheetButtonDismiss))
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                
                if containerVerticalSizeClass == .compact {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text(.localizable(.generalButtonClose))
                    }
                }
                
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                    case .exportImage:
                        ExportImageView()
                    case .exportFile:
                        ExportFileView(file: sharedFile)
#if DEBUG
                    case .svgPreview(let url):
                        svgPreviewView(url: url)
#endif
                }
            }
            .padding(40)
#if os(macOS)
            .toolbar(.hidden, for: .windowToolbar)
#endif
        }
    }
    
#if DEBUG
    @MainActor @ViewBuilder
    private func svgPreviewView(url: URL) -> some View {
        SVGPreviewWebView(svgURL: url)
    }
#endif
}

#if canImport(AppKit)
struct SVGPreviewWebView: NSViewRepresentable {
    var svgURL: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.loadFileURL(svgURL, allowingReadAccessTo: svgURL.deletingLastPathComponent())
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        
    }
}
#elseif canImport(UIKit)
struct SVGPreviewWebView: UIViewRepresentable {
    var svgURL: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.loadFileURL(svgURL, allowingReadAccessTo: svgURL.deletingLastPathComponent())
        return webView
    }
    
    func updateUIView(_ nsView: WKWebView, context: Context) {
        
    }
}
#endif

struct ShareViewLagacy: View {
    @Environment(\.dismiss) var dismiss

    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var exportState: ExportState

    var sharedFile: File
    
    enum Route: Hashable {
        case exportImage
        case exportFile
    }
    
    @State private var route: [Route] = []
    
    var body: some View {
        ZStack {
            if route.last == .exportImage {
                ExportImageView {
                    route.removeLast()
                }
                .transition(.fade)
            } else if route.last == .exportFile {
                ExportFileView(file: sharedFile) {
                    route.removeLast()
                }
                .transition(.fade)
            } else {
                homepage()
                    .transition(.identity)
            }
        }
        .animation(.default, value: route.last)
        .padding(.horizontal, 40)
        .frame(width: 400, height: 300)
    }
    
#if os(iOS)
    @State private var exportedPDFURL: URL?
#endif
    
    @MainActor @ViewBuilder
    private func homepage() -> some View {
        VStack(spacing: 20) {
            Text(.localizable(.exportSheetHeadline))
                .font(.largeTitle)

            HStack(spacing: 14) {
                SquareButton(title: .localizable(.exportSheetButtonImage), icon: .photo) {
                    route.append(Route.exportImage)
                }
                
                SquareButton(title: .localizable(.exportSheetButtonFile), icon: .doc) {
                    route.append(Route.exportFile)
                }
                SquareButton(title: .localizable(.exportSheetButtonPDF), icon: .docRichtext, priority: .background) {
                    do {
#if os(macOS)
                        let imageData = try await exportState.exportCurrentFileToImage(
                            type: .png,
                            embedScene: false,
                            withBackground: true
                        ).data
                        if let image = NSImage(dataIgnoringOrientation: imageData) {
                            exportPDF(image: image, name: sharedFile.name)
                        }
#elseif os(iOS)
                        let imageData = try await exportState.exportCurrentFileToImage(
                            type: .png,
                            embedScene: false,
                            withBackground: true
                        ).data
                        if let image = UIImage(data: imageData) {
                            self.exportedPDFURL = try exportPDF(image: image, name: sharedFile.name)
                        }
#endif
                    } catch {
                        alertToast(error)
                    }
                }
#if os(iOS)
                .activitySheet(item: $exportedPDFURL)
#endif

//                ShareLink(
//                    item: PDFFile(
//                        name: sharedFile.name,
//                        makeImage: {
//                            do {
//                                let imageData = try await exportState.exportCurrentFileToImage(
//                                    type: .png,
//                                    embedScene: false,
//                                    withBackground: true
//                                ).data
//                                return UIImage(data: imageData) ?? UIImage(systemSymbol: .exclamationmarkTriangle)
//                            } catch {
//                                return UIImage(systemSymbol: .exclamationmarkTriangle)
//                            }
//                        }
//                    ),
//                    preview: SharePreview(sharedFile.name ?? "Excalidraw PDF")
//                ) {
//                    SquareButton.label(.localizable(.exportSheetButtonPDF), icon: .docRichtext)
//                }
//                .buttonStyle(ExportButtonStyle())
#if os(macOS)
                SquareButton(title: .localizable(.exportSheetButtonArchive), icon: .archivebox) {
                    do {
                        try archiveAllFiles()
                    } catch {
                        alertToast(error)
                    }
                }
#endif
            }
            
            Button {
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text(.localizable(.generalButtonClose))
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

}

fileprivate struct SquareButton: View {
    @Environment(\.isEnabled) var isEnabled
    
    var title: LocalizedStringKey
    var icon: SFSymbol
    var action: () async -> Void
    var priority: TaskPriority?
    
    init(
        title: LocalizedStringKey,
        icon: SFSymbol,
        priority: TaskPriority? = nil,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
        self.priority = priority
    }
    
    @State private var isLoading = false
    
    var body: some View {
        Button {
            Task.detached(priority: priority) {
                await MainActor.run {
                    isLoading = true
                }
                await action()
                await MainActor.run {
                    isLoading = false
                }
            }
        } label: {
            Self
                .label(title, icon: icon)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView()
                    }
                }
                .animation(.default, value: isLoading)
        }
        .buttonStyle(ExportButtonStyle())
    }
    
    @MainActor @ViewBuilder
    static func label(_ title: LocalizedStringKey, icon: SFSymbol) -> some View {
        VStack {
            Image(systemSymbol: icon)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 10)
            Text(title)
        }
    }
}



struct ExportButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    @State private var isHovered = false
    
    let size: CGFloat = 86
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .padding()
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isEnabled ?
                                (
                                    isPressed ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(isHovered ? .ultraThickMaterial : .regularMaterial)
                                ) : AnyShapeStyle(Color.clear)
                            )
                        if #available(macOS 13.0, iOS 17.0, *) {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.separator, lineWidth: 0.5)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.gray, lineWidth: 0.5)
                        }
                    }
                    .animation(.default, value: isHovered)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

#if DEBUG
#Preview {
    if #available(macOS 13.0, *) {
        ShareView(sharedFile: .preview)
            .environmentObject(ExportState())
    } else {
        ShareViewLagacy(sharedFile: .preview)
            .environmentObject(ExportState())
    }
}
#endif
