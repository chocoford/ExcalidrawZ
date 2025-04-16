//
//  WebView+UI.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit

extension Notification.Name {
    static let shouldOpenExternalURL = Notification.Name("ShouldOpenExternalURL")
}

extension Notification {
    static func shouldOpenExternalURL(url: URL) -> Notification {
        Notification(name: .shouldOpenExternalURL, object: url)
    }
}

extension ExcalidrawCore: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
//        dump(navigationAction)
        print(navigationAction.targetFrame, navigationAction.request)
        if let url = navigationAction.request.url {
            NotificationCenter.default.post(.shouldOpenExternalURL(url: url))
        }
        return nil
    }
    
#if os(macOS)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { res in
            if res == .OK {
                completionHandler(panel.urls)
            } else {
                completionHandler(nil)
            }
        }
//        if panel.runModal() == .OK {
//            completionHandler(panel.urls)
//        } else {
//            completionHandler(nil)
//        }
    }
#endif
}
