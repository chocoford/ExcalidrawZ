//
//  WebView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit
import Combine

class ExcaliDrawWebView: WKWebView {
    static let shared: WKWebView //= .init()
    = {
        let webView = WKWebView()
        webView.load(URLRequest(url: URL(string: "https://excalidraw.com")!))
        return webView
    }()
}

struct WebView {
    let webView: WKWebView = ExcaliDrawWebView.shared
    var currentFile: URL?
        
    @Binding var loading: Bool
    
    init(url: URL, currentFile: URL? = nil, isLoading: Binding<Bool>) {
        self._loading = isLoading
        self.currentFile = currentFile
        executeScript()
    }
}

#if os(macOS)
extension WebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "iosListener")
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
}


extension WebView {
    func getScript(url: URL?) -> String {
        if let url = url {
            guard let data = try? Data(contentsOf: url) else { return "" }
            
            
            var buffer = [UInt8].init(repeating: 0, count: data.count)
            data.copyBytes(to: &buffer, count: data.count)
            
            let jsCode =
"""
(() => {
    let uint8Array = new Uint8Array(\(buffer));
    let file = new File([uint8Array], "abc.excalidraw", {
      lastModified: new Date(2020, 1, 1).getTime(),
      type: "",
    });

    function FakeDataTransfer(file) {
      this.dropEffect = "all";
      this.effectAllowed = "all";
      this.items = [{getAsFileSystemHandle: async () => null}];
      this.types = ["Files"];
      this.getData = function () {
        return file;
      };
      this.files = {
        item: (index) => {
          return file;
        },
      };
    }

    let fakeDropEvent = new DragEvent("drop", {bubbles: true});
    fakeDropEvent.simulated = true;
    Object.defineProperty(fakeDropEvent, "dataTransfer", {
      value: new FakeDataTransfer(file),
    });

    let node = document.querySelector(".excalidraw-container");
    node.dispatchEvent(fakeDropEvent);
})()
"""
            return jsCode
        }
        return ""
    }
    
    func executeScript() {
        guard let url = currentFile else { return }
        self.webView.evaluateJavaScript(getScript(url: url)) { response, error in
            if let error = error {
                dump(error)
                return
            }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                loading = false
            }
        }
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
        return .allow
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
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
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("didFinish")
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
        // TODO: Can not get file name, cuz appState.name is undefined.
        let url = AppFileManager.shared.assetDir.appendingPathComponent("Untitled", conformingTo: .fileURL).appendingPathExtension("excalidraw")
        return url
    }
}

extension WebViewCoordinator: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        dump(navigationAction)
        return nil
    }
}

extension WebViewCoordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        dump(message)
    }
    
}


#elseif os(iOS)

#endif
