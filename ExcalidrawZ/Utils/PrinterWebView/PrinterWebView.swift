//
//  PrinterWebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/21/25.
//

import SwiftUI
import WebKit
import SwiftUIIntrospect
import os.log

//#if DEBUG
//class PrinterWebView: WKWebView {
//    init(filename: String) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    public func print(fileURL: URL) async {}
//}
//#else


class PrinterWebView: WKWebView {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PrinterWebView")
    
    var filename: String
#if canImport(AppKit)
    typealias PlatformRect = NSRect
    var printInfo: NSPrintInfo = {
        let printInfo = NSPrintInfo.shared
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        return printInfo
    }()
#elseif canImport(UIKit)
    typealias PlatformRect = CGRect
#endif

    
    init(filename: String) {
        self.filename = filename
#if canImport(AppKit)
        let frame = PlatformRect(
            origin: .zero,
            size: CGSize(
                width: printInfo.paperSize.width,
                height: printInfo.paperSize.height
            )
        )
#elseif canImport(UIKit)
        let frame = PlatformRect(
            origin: .zero,
            size: CGSize(width: 595, height: 842) // standard A4
        )
#endif
        
        let preferences = WKPreferences()
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        
        super.init(
            frame: frame,
            configuration: configuration
        )
        
        self.navigationDelegate = self
    }
    
#if canImport(AppKit)
    fileprivate var printRequests: [URL : () -> Void] = [:]
    func print(fileURL: URL) async {
        self.load(URLRequest(url: fileURL))
        await withCheckedContinuation { continuation in
            printRequests[fileURL] = {
                self.printRequests.removeValue(forKey: fileURL)
                continuation.resume()
            }
        }
    }
#elseif canImport(UIKit)
    fileprivate var printRequests: [URL : (URL?) -> Void] = [:]
    func exportPDF(fileURL: URL) async -> URL? {
        self.load(URLRequest(url: fileURL))
        return await withCheckedContinuation { continuation in
            printRequests[fileURL] = { url in
                self.printRequests.removeValue(forKey: fileURL)
                continuation.resume(returning: url)
            }
        }
    }
#endif
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PrinterWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if canImport(AppKit)
        let printOperation = webView.printOperation(with: printInfo)
        printOperation.view?.frame = webView.frame // important
        if let window = webView.window ?? NSApp.keyWindow {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            Swift.print("No window for print")
        }
        
        if let url = webView.url {
            self.printRequests[url]?()
        }
#elseif canImport(UIKit)
        Task.detached {
            let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "\(await self.filename).pdf"
            )
            do {
                let data = try await self.generatePDF(from: webView)
                try data.write(to: pdfURL)
                if let url = await webView.url {
                    await self.printRequests[url]?(pdfURL)
                }
            } catch {
                self.logger.error("generatePDF failed: \(error)")
                if let url = await webView.url {
                    await self.printRequests[url]?(nil)
                }
            }

        }
#endif
    }
    
    func generatePDF(from webView: WKWebView) async throws -> Data {
        if #available(iOS 14.0, *) {
            let pdfConfig = WKPDFConfiguration()
            return try await webView.pdf(configuration: pdfConfig)
        } else {
            struct NotSupportError: LocalizedError {
                var errorDescription: String? {
                    "PDF generation is not supported on iOS versions below 14."
                }
            }
            throw NotSupportError()
        }
    }
}
//#endif
