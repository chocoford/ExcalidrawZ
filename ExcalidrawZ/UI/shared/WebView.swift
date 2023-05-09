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
    
    init(store: AppStore, currentFile: Binding<File?>, loading: Binding<Bool>) {
        self.store = store
        self._currentFile = currentFile
        self._loading = loading
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
        guard !loading else { return }

        if (currentFile == nil && self.lsMonitorTimer?.isValid == false) || currentFile?.id != previousFileID {
            self.lsMonitorTimer?.invalidate()
        }
        DispatchQueue.main.async {
            // Fix Bug: Will cause infinity loop: startWatchingLocalStorage -> set lsMonitorTimer -> updateNSView -> startWatchingLocalStorage
            // (currentFile == nil && self.lsMonitorTimer?.isValid == false) fix this.
            if (currentFile == nil && self.lsMonitorTimer?.isValid == false) || currentFile?.id != previousFileID {
                self.lsMonitorTimer?.invalidate()
                self.loadCurrentFile {
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
        logger.info("loadCurrentFile: \(currentFile?.name ?? "nil"), timer: \(lsMonitorTimer?.isValid == true ? "valid" : "invalid")")
        
        let script = getScript(from: currentFile)
        
        self.webView.evaluateJavaScript(script) { response, error in
            if let error = error {
                dump(error)
                return
            }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation {
                        self.loading = false
                    }
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
            let currentFileID = self.currentFile?.id
            self.webView.evaluateJavaScript(script) { response, error in
                if let error = error {
                    self.logger.error("\(error)")
                    return
                }
                guard let versionString = response as? String else {
                    self.logger.error("response is not string: \(String(describing: response))")
                    return
                }
                guard currentFileID == self.currentFile?.id else {
                    self.logger.debug("not current file, discard.")
                    return
                }
                
                if let version = Int(versionString),
                   self.lastVersion < version {
                    self.logger.debug("version changed")
                    if self.lastVersion > 0 {
                        self.saveCurrentFile()
                        self.saveTheme()
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
        let file = self.currentFile
        logger.info("<saveCurrentFile> start saving: \(file?.name ?? "nil")")
        let getExcalidrawScript = "localStorage.getItem('excalidraw')"
        self.webView.evaluateJavaScript(getExcalidrawScript) { response, error in
            if let error = error {
                dump(error)
                return
            }
            
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
    
    /// `true` if is dark mode.
    func getIsDark() async -> Bool {
        let getExcalidrawScript = "localStorage.getItem('excalidraw-theme')"
        return await withCheckedContinuation { continuation in
            self.webView.evaluateJavaScript(getExcalidrawScript) { response, error in
                if let error = error {
                    dump(error)
                    continuation.resume(returning: false)
                    return
                }
                guard let theme = response as? String else {
                    self.logger.error("response is not string: \(String(describing: response))")
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(with: .success(theme == "dark"))
            }
        }
    }
    
    func saveTheme() {
        let getExcalidrawScript = "localStorage.getItem('excalidraw-theme')"
        self.webView.evaluateJavaScript(getExcalidrawScript) { response, error in
            if let error = error {
                dump(error)
                return
            }
            guard let theme = response as? String else {
                self.logger.error("response is not string: \(String(describing: response))")
                return
            }
            UserDefaults.standard.set(theme == "dark", forKey: "isDarkMode")
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

    func hideDialogs() {
        let script = "document.querySelector('.excalidraw-modal-container').style.display = 'none';"
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
        
    var downloads: [URLRequest : URL] = [:]
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
        Task { @MainActor in
            let isDark = await self.parent.getIsDark()
            if UserDefaults.standard.bool(forKey: "isDarkMode") && !isDark {
                webView.evaluateJavaScript("localStorage.setItem(\"excalidraw-theme\", \"dark\")") { (result, error) in
                    webView.reload()
                }
            } else {
                self.parent.loading = false
                self.parent.hideDropdownButton()
                self.parent.hideDialogs();
                self.parent.loadCurrentFile {
                    self.parent.startWatchingLocalStorage()
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
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("didFailProvisionalNavigation: \(error)")
    }
}

extension WebViewCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let fileManager: FileManager = FileManager.default
        let directory: URL
        do {
            if #available(macOS 13.0, *) {
                directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: .applicationSupportDirectory, create: true)
            } else if let temp = URL(string: NSTemporaryDirectory()) {
                directory = temp
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } else {
                return nil
            }
            
            let fileExtension = suggestedFilename.components(separatedBy: ".").last ?? "png"
            let fileName = await self.parent.currentFile?.name?.appending(".\(fileExtension)") ?? suggestedFilename
            
            let url = directory.appendingPathComponent(fileName, conformingTo: .image)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            
            if let request = download.originalRequest {
                self.downloads[request] = url;
            }
            print(url.isFileURL) // false
            DispatchQueue.main.async {
                self.parent.store.send(.setExportingState(.init(url: url, download: download, done: false)))
            }

            return url;
        } catch {
            logger.error("\(error)")
            return nil
        }
    }

    @MainActor
    func downloadDidFinish(_ download: WKDownload) {
        guard let request = download.originalRequest,
              let url = downloads[request] else { return }
        logger.info("download did finished: \(url)")
        if self.parent.store.state.exportingState != nil {
            self.parent.store.send(.setExportingState(.init(url: url, download: download, done: true)))
        }
        downloads.removeValue(forKey: request)
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
