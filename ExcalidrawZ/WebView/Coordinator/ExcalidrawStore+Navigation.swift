//
//  Coordinator+Navigation.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit

extension ExcalidrawWebView.Coordinator: WKNavigationDelegate {
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
//            print(url)
//            do {
//                let script = """
//fetch('\(url.absoluteString)')
//.then(response => response.blob())
//.then(blob => blob.arrayBuffer())
//.then(arrayBuffer => { window.webkit.messageHandlers.excalidrawZ.postMessage({
//        event: 'blobData',
//        data: arrayBuffer
//    });
//})
//.catch((error) => {
//    console.error(error)
//});
//0;
//"""
//                try await self.webView.evaluateJavaScript(script)
//            } catch {
//                self.parent.store.send(.setError(.init(error)))
//            }
//            
//            return .cancel
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
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("did finish navigation")
        self.parent.isLoading = false
        // load file when finishing navigation
        Task { @MainActor in
            do {
                try await self.loadFile(from: parent.fileState.currentFile)
            } catch {
                self.parent.onError(error)
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
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
//        logger.error("didFailProvisionalNavigation: \(error)")
        self.parent.onError(error)
    }
}
