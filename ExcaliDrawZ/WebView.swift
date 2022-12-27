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
import OSLog

class ExcaliDrawWebView: WKWebView {
    static let shared: WKWebView //= .init()
    = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: URL(string: "https://excalidraw.com")!))
        return webView
    }()
}

struct WebView {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebView")
    let webView: WKWebView = ExcaliDrawWebView.shared
    
    @Binding var currentFile: URL?
    @Binding var loading: Bool
        
    init(currentFile: Binding<URL?>, isLoading: Binding<Bool>) {
        self._loading = isLoading
        self._currentFile = currentFile
        if !webView.isLoading {
            executeScript()
        }
        
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
        context.coordinator.parent = self
        context.coordinator.watchLocalStorage()
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
        logger.info("executeScript for file: \(url.lastPathComponent)")
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
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebViewCoordinator")
    var parent: WebView
    
    var lsMonitorTimer: Timer?
    
    init(_ parent: WebView) {
        self.parent = parent
    }
    
    var lastVersion: Int = 0
    
    func watchLocalStorage() {
        logger.info("Start watching local storage.")
        let script = "localStorage.getItem('version-files')"
        lsMonitorTimer?.invalidate()
        lsMonitorTimer = Timer.scheduledTimer(withTimeInterval: parent.currentFile == nil ? 1.0 : 5.0, repeats: true) { _ in
            if self.parent.webView.isLoading { return }
            self.parent.webView.evaluateJavaScript(script) { response, error in
                if let error = error {
                    dump(error)
                    return
                }
                self.logger.debug("current version: \(response as? String ?? ""), lastVersion: \(self.lastVersion)")
                if let versionString = response as? String,
                   let version = Int(versionString),
                   self.lastVersion < version {
                    if self.lastVersion > 0 {
                        self.saveCurrentFile()
                    }
                    self.lastVersion = version
                }
            }
        }
    }
    
    func saveCurrentFile() {
        guard let path = Bundle.main.url(forResource: "FakeSaveCommand", withExtension: "js"),
              let data = try? Data(contentsOf: path),
              let script = String(data: data, encoding: .utf8) else { return }
        self.parent.webView.evaluateJavaScript(script) { response, error in
            if let error = error {
                dump(error)
                return
            }
            self.lastVersion = Int((Date().timeIntervalSince1970 + 2) * 1000)
        }
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
        parent.executeScript()
        parent.loading = false
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
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        dump(error)
    }
}

extension WebViewCoordinator: WKDownloadDelegate {
    /// generate a temp name by adding `_` in front of the original name.
    ///
    /// After downloading done, it will move the temp `_<originName>` file to overwrite the original file.
    func generateTempSavedFile() -> URL? {
        guard let currentFile = parent.currentFile else { return nil }
        let fileName = currentFile.lastPathComponent
        let newFileName = "_" + fileName
        let url = currentFile.deletingLastPathComponent().appendingPathComponent(newFileName, conformingTo: .fileURL)
        return url
    }

    /// if `currentFile` is nil, will generate a file named `Untitled`.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        logger.info("on download. currentFile: \(self.parent.currentFile?.lastPathComponent ?? "unknwon")")

        if self.parent.currentFile == nil {
            let url = AppFileManager.shared.generateNewFileName()
            self.parent.currentFile = url
        }
        
        if let url = generateTempSavedFile() {
            logger.info("on download. currentFile: \(self.parent.currentFile?.lastPathComponent ?? "unknwon"), save to file: \(url.lastPathComponent)")
            return url
        }
        return nil
    }
    
    /// callback on download finished
    ///
    /// it overwrite the original file.
    func downloadDidFinish(_ download: WKDownload) {
        logger.info("download did finish! currentFile: \(self.parent.currentFile?.lastPathComponent ?? "unknwon")")
        guard let currentFile = parent.currentFile else { return }
        guard let url = generateTempSavedFile() else { return }
        do {
            try? FileManager.default.removeItem(at: currentFile)
            try FileManager.default.moveItem(at: url, to: currentFile)
        } catch {
            logger.error("\(error)")
        }
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
