//
//  Coordinator+Navigation.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit
import CoreData

extension ExcalidrawCore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        return (.allow, preferences)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }
    
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let url = navigationResponse.response.url,
           url.scheme == "blob" {
            return .download
        }
        if navigationResponse.canShowMIMEType {
            return .allow
        } else {
            return .download
        }
    }
    
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("didFail: \(error)")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("didFinish - URL: \(webView.url?.absoluteString ?? "nil"), hasInjectIndexedDBData: \(self.hasInjectIndexedDBData)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isNavigating = false
            Task {
                do {
                    // Use the extracted injection method
                    let injectedCount = try await self.injectAllMediaItems()
                    self.logger.info("Injected \(injectedCount) MediaItems on initial load")
                    
                    try await Task.sleep(nanoseconds: UInt64(1e+9 * 0.3))
                    
                    // Open Collab mode if needed.
                    if self.parent?.type == .collaboration,
                       self.parent?.file?.roomID?.isEmpty != false,
                       let file = self.parent?.file,
                       let content = file.content {
                        // load file content
                        try await self.webActor.loadFile(
                            id: file.id,
                            data: content,
                            force: true
                        )
                        // open collab mode
                        try await self.openCollabMode()
                    }
                    
                } catch {
                    self.parent?.onError(error)
                }
            }
        }
    }
        
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        logger.info("didCommit...")
        self.parent?.loadingState = .loading
        DispatchQueue.main.async {
            self.isNavigating = true
            self.isDocumentLoaded = false
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.info("didStartProvisionalNavigation...")
        self.parent?.loadingState = .loading
        DispatchQueue.main.async {
            self.isNavigating = true
            self.isDocumentLoaded = false
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // logger.error("[ExcalidrawCore] didFailProvisionalNavigation: \(error)")
        self.parent?.loadingState = .error(error)
        self.publishError(error)
    }
}
