//
//  WebView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit


struct WebView {
    let webView: WKWebView
    
    init(url: URL) {
        webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: url))
    }
}

#if os(macOS)
extension WebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        
    }
    
}


extension WebView {
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
}

class WebViewCoordinator: NSObject {
       var parent: WebView

       init(_ parent: WebView) {
           self.parent = parent
       }
}

extension WebViewCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        return (.allow, preferences)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        dump(navigationAction)
        return .allow
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        dump(navigationResponse)
        if let scheme = navigationResponse.response.url?.scheme,
           scheme == "blob" {
            return .download
        }
        if navigationResponse.canShowMIMEType {
            return .allow
        } else {
            return .download
        }
    }
    
    
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        dump(error)
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("didStartProvisionalNavigation")
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        dump(navigation)
    }
}

extension WebViewCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let url = AppFileManager.shared.assetDir.appendingPathComponent(UUID().uuidString, conformingTo: .fileURL)
//        dump(url, name: "download url")
        return url
    }
    
    
}

extension WebViewCoordinator: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        dump(navigationAction)
        return nil
    }
}

#elseif os(iOS)

#endif
