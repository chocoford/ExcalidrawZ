//
//  LibraryBrowserSheet.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import SwiftUI
import WebKit
import Logging

/// In-app browser for `https://libraries.excalidraw.com`. Intercepts the site's
/// "Add to Excalidraw" button (which normally opens
/// `https://excalidraw.com/?addLibrary=<url>` in a new tab) and pipes the
/// referenced `.excalidrawlib` JSON into the existing import flow via the
/// `.addLibrary` notification — the user never leaves the app.
struct LibraryBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast

    /// Invoked when the user picks "Import from file" — the parent should open
    /// the system file importer. Called *before* dismissal; the parent typically
    /// stashes a flag and triggers the importer in the sheet's `onDismiss`
    /// handler so the two presentations don't fight each other.
    var onRequestManualImport: (() -> Void)? = nil

    @State private var isLoading: Bool = true
    @State private var pageTitle: String = ""
    @State private var importInFlight: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                LibraryBrowserWebView(
                    isLoading: $isLoading,
                    pageTitle: $pageTitle,
                    onAddLibrary: handleAddLibrary
                )
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 540)
#endif
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizable: .libraryImportBrowserSheetTitle)
                    .font(.headline)
                Text(pageTitle.isEmpty
                     ? "libraries.excalidraw.com"
                     : pageTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer()
            if importInFlight {
                ProgressView()
                    .controlSize(.small)
            }
            if onRequestManualImport != nil {
                Button {
                    onRequestManualImport?()
                    dismiss()
                } label: {
                    Label(.localizable(.libraryImportBrowserSheetButtonImportFromFile), systemSymbol: .squareAndArrowDown)
                }
                .modernButtonStyle(style: .glass, shape: .capsule)
            }
            Button {
                dismiss()
            } label: {
                Text(localizable: .generalButtonDone)
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, shape: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func handleAddLibrary(_ url: URL) {
        guard !importInFlight else { return }
        importInFlight = true
        Task { @MainActor in
            defer { importInFlight = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                var library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data)
                if library.name == nil {
                    library.name = url.deletingPathExtension().lastPathComponent
                }
                NotificationCenter.default.post(name: .addLibrary, object: [library])
                dismiss()
            } catch {
                alertToast(error)
            }
        }
    }
}

// MARK: - WKWebView wrapper

#if canImport(AppKit)
private typealias _ViewRepresentable = NSViewRepresentable
#elseif canImport(UIKit)
private typealias _ViewRepresentable = UIViewRepresentable
#endif

private struct LibraryBrowserWebView: _ViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    var onAddLibrary: (URL) -> Void

    private static let homeURL = URL(string: "https://libraries.excalidraw.com")!

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

#if canImport(AppKit)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
#elseif canImport(UIKit)
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
#endif

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.homeURL))
        context.coordinator.webView = webView
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: LibraryBrowserWebView
        weak var webView: WKWebView?
        private let logger = Logger(label: "LibraryBrowser")

        init(parent: LibraryBrowserWebView) {
            self.parent = parent
        }

        // MARK: Loading state / title

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.pageTitle = webView.title ?? ""
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // MARK: Intercept "Add to Excalidraw"

        /// Catches direct navigations like `location.href = "..."`.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, let libURL = libraryURL(from: url) {
                decisionHandler(.cancel)
                parent.onAddLibrary(libURL)
                return
            }
            decisionHandler(.allow)
        }

        /// Catches `target="_blank"` clicks (the actual behavior of the Add button).
        /// Returning `nil` plus our own handling prevents WebKit from creating a popup.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, let libURL = libraryURL(from: url) {
                parent.onAddLibrary(libURL)
            }
            return nil
        }

        /// Extracts the `addLibrary=<url>` query parameter when the navigation
        /// target is excalidraw.com. Returns nil for any other URL.
        private func libraryURL(from url: URL) -> URL? {
            guard let host = url.host?.lowercased(),
                  host == "excalidraw.com" || host.hasSuffix(".excalidraw.com"),
                  host != "libraries.excalidraw.com" else {
                return nil
            }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let raw = components.queryItems?.first(where: { $0.name == "addLibrary" })?.value,
                  let libURL = URL(string: raw),
                  ["http", "https"].contains(libURL.scheme?.lowercased() ?? "") else {
                return nil
            }
            return libURL
        }
    }
}
