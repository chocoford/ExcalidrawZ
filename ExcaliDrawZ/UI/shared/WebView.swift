//
//  WebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import OSLog

class ExcalidrawWebView: WKWebView {
    static let shared: WKWebView = makeWebView()
    
    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        let urlRequest = URLRequest(url: URL(string: "https://excalidraw.com")!)
        DispatchQueue.main.async {
            webView.load(urlRequest)
        }
        return webView
    }
}

struct WebView {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebView")
    // must use a static variable
    let webView: WKWebView = ExcalidrawWebView.shared
    
    @ObservedObject var store: AppStore
    @Binding var currentFile: File?
    @Binding var loading: Bool
    
    @State private var previousFileID: UUID? = nil
    @State private var lsMonitorTimer: Timer? = nil
    @State private var lastVersion: Int = 0

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
        guard !loading else { return }
//        Task { @MainActor in
        DispatchQueue.main.async {
            if currentFile == nil || currentFile?.id != previousFileID {
                self.lsMonitorTimer?.invalidate()
                self.loadCurrentFile{
                    self.startWatchingLocalStorage()
                }
            }
        }
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
}


extension WebView {
    func getScript(from file: File?) -> String {
        guard let data = try? file?.content ?? Data(contentsOf: Bundle.main.url(forResource: "template", withExtension: "excalidraw")!)
        else { return "" }
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        
        let jsCode =
"""
(() => {
    let uint8Array = new Uint8Array(\(buffer));
    let file = new File([uint8Array], "file.excalidraw", {
      lastModified: new Date().getTime(),
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
    
    /// Load current `File`.
    ///
    /// This function will simulate the *file drop* operation to `excalidraw.com`.
    /// It evaluates `javascript` code that dispatch `DragEvent` to the specific `HTMLElement`.
    @MainActor
    func loadCurrentFile(callback: @escaping () -> Void) {
        previousFileID = self.currentFile?.id
        logger.info("loadCurrentFile: \(currentFile?.name ?? "nil")")
        
        let script = getScript(from: currentFile)
        
        self.webView.evaluateJavaScript(script) { response, error in
            if let error = error {
                dump(error)
                return
            }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.loading = false
                }
            }
            callback()
        }
//        do {
//            let response = try await self.webView.evaluateJavaScript(script)
//            logger.info("loadCurrentFile done: \(response as? String ?? "nil")")
//            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
//                loading = false
//            }
//        } catch {
//            logger.error("evaluateJavaScript error: \(error)")
//        }
    }
    
    func startWatchingLocalStorage() {
        self.lsMonitorTimer?.invalidate()
        if self.currentFile?.inTrash == true {
            self.logger.info("InTrash file, skip watching local storage")
            return;
        }
        self.logger.info("Start watching local storage.")
        let script = "localStorage.getItem('version-files');"
        self.lsMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//            let currentFileID = self.currentFile?.id
            self.webView.evaluateJavaScript(script) { response, error in
                if let error = error {
                    self.logger.error("\(error)")
                    return
                }
                guard let versionString = response as? String else {
                    self.logger.error("response is not string: \(String(describing: response))")
                    return
                }
//                guard currentFileID == self.currentFile?.id else {
//                    self.logger.debug("not current file, discard.")
//                    return
//                }
                
                if let version = Int(versionString),
                   self.lastVersion < version {
                    self.logger.debug("version changed")
                    if self.lastVersion > 0 {
                        self.saveCurrentFile()
                    }
                    self.lastVersion = version
                }
            }
        }
    }
    
    /// Save `currentFile` or creating if neccessary.
    ///
    /// This function will get the local storage of `excalidraw.com`.
    /// Then it will set the data got from local storage to `currentFile`.
    func saveCurrentFile() {
        logger.info("<saveCurrentFile> saving: \(self.currentFile?.name ?? "nil")")
        let getExcalidrawScript = "localStorage.getItem('excalidraw')"
        let file = self.currentFile
        self.webView.evaluateJavaScript(getExcalidrawScript) { response, error in
            if let error = error {
                dump(error)
                return
            }
//            guard self.currentFile?.id == fileID else {
//                logger.info("<saveCurrentFile> File has changed. Ignored.")
//                return
//            }
            
            guard let response = response as? String  else { return }
            do {
                guard let resData = response.data(using: .utf8) else { throw AppError.fileError(.createError) }
                if let file = file {
                    // parse current file content
                    try file.updateElements(with: resData)
                } else {
                    // create the file
                    DispatchQueue.main.async {
                        self.store.send(.newFile(resData))
                    }
                }
            } catch {
                dump(error)
            }
            self.lastVersion = Int((Date().timeIntervalSince1970 + 2) * 1000)
        }
    }
    
    @MainActor
    func changeCurrentFile(_ file: File?) {
        logger.debug("change current file: \(file?.name ?? "nil")")
        currentFile = file
    }
    
    func hideDropdownButton() {
        logger.info("remove dropdown menu button and its decor.")
        let script = "document.querySelector('.App-menu_top__left').firstElementChild.style.display = 'none';"
        self.webView.evaluateJavaScript(script)
    }
}

class WebViewCoordinator: NSObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebViewCoordinator")
    var parent: WebView
    
    var lsMonitorTimer: Timer?
    var downloadCache: [String : Data] = [:]
    
    init(_ parent: WebView) {
        self.parent = parent
    }
        
    var downloads: [WKDownload : (URL, File)] = [:]
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
        logger.error("didFail: \(error)")
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("did finish navigation")
//        Task { @MainActor in
        DispatchQueue.main.async {
            self.parent.loading = false
            self.parent.hideDropdownButton()
            self.parent.loadCurrentFile {
                self.parent.startWatchingLocalStorage()
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
        logger.error("didFailProvisionalNavigation: \(error)")
    }
}

extension WebViewCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        return nil
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
