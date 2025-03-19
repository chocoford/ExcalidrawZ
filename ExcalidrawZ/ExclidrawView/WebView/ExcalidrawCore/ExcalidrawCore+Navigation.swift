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
        logger.error("[ExcalidrawCore] didFail: \(error)")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("[ExcalidrawCore] did finish navigation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.hasInjectIndexedDBData {
                // Should import medias as soon as possible.
                // And It is required to reload after injected.
                self.logger.info("[ExcalidrawCore] Start insert medias to IndexedDB.")
                Task {
                    do {
                        let context = PersistenceController.shared.container.viewContext
                        let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
                        
                        let allMedias = try context.fetch(allMediasFetch)
                        try await self.insertMediaFiles(
                            allMedias.compactMap{
                                .init(mediaItem: $0)
                            }
                        )
                        self.hasInjectIndexedDBData = true
                        
                        // Open Collab mode if needed.
                        if self.parent?.type == .collaboration,
                           self.parent?.file?.roomID?.isEmpty != false,
                           let file = self.parent?.file,
                           let fileContent = file.content {
                            // load file content
                            try await self.webActor.loadFile(
                                id: file.id,
                                data: fileContent,
                                force: true
                            )
                            // open collab mode
                            try await self.openCollabMode()
                        }
                        
                        self.isNavigating = false
                    } catch {
                        self.parent?.onError(error)
                    }
                }
                // self.isNavigating = false
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
        self.parent?.loadingState = .loading
        DispatchQueue.main.async {
            self.isNavigating = true
            self.isDocumentLoaded = false
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
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
