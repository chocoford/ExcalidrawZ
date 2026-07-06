//
//  PrinterWebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/21/25.
//

import SwiftUI
import WebKit
import SwiftUIIntrospect
import Logging
//
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
//
//    func exportPDF(fileURL: URL) async -> URL? { nil }
//    func exportPDFData(fileURL: URL) async throws -> Data { Data() }
//}
//#else

class PrinterWebView: WKWebView {
    let logger = Logger(label: "PrinterWebView")
    
    var filename: String
#if canImport(AppKit)
    typealias PlatformRect = NSRect
    var printInfo: NSPrintInfo = {
        // Create a new instance instead of modifying shared
        let printInfo = NSPrintInfo()
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

    fileprivate var pdfDataRequests: [URL : (Result<Data, Error>) -> Void] = [:]
    
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

    func exportPDFData(fileURL: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            pdfDataRequests[fileURL] = { result in
                self.pdfDataRequests.removeValue(forKey: fileURL)
                continuation.resume(with: result)
            }
            self.load(URLRequest(url: fileURL))
        }
    }
}

extension PrinterWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url,
           let pdfDataRequest = pdfDataRequests[url] {
            Task { @MainActor in
                do {
                    let data = try await generatePDF(from: webView)
                    pdfDataRequest(.success(data))
                } catch {
                    logger.error("generatePDF failed: \(error)")
                    pdfDataRequest(.failure(error))
                }
            }
            return
        }

#if canImport(AppKit)
        let printOperation = webView.printOperation(with: printInfo)
        printOperation.view?.frame = webView.frame // important

        // Enable print and progress panels so user can configure settings
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.printPanel.options.formUnion([
            .showsCopies,
            .showsPageRange,
            .showsPaperSize,
            .showsOrientation,
            .showsScaling,
            .showsPreview,
            .showsPageSetupAccessory,
            .showsPrintSelection
        ])

        if let window = webView.window ?? NSApp.keyWindow {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            logger.warning("No window available for print operation")
        }

        if let url = webView.url {
            self.printRequests[url]?()
        }
#elseif canImport(UIKit)
        Task { @MainActor in
            let pdfURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(filename).pdf")
            do {
                let data = try await self.generatePDF(from: webView)
                try data.write(to: pdfURL)
                if let url = webView.url {
                    self.printRequests[url]?(pdfURL)
                }
            } catch {
                self.logger.error("generatePDF failed: \(error)")
                if let url = webView.url {
                    self.printRequests[url]?(nil)
                }
            }

        }
#endif
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        failPDFDataRequest(for: webView.url, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failPDFDataRequest(for: webView.url, error: error)
    }
    
    @MainActor
    func generatePDF(from webView: WKWebView) async throws -> Data {
        if #available(macOS 11.0, iOS 14.0, *) {
            let pdfConfig = WKPDFConfiguration()
            return try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: pdfConfig) { result in
                    continuation.resume(with: result)
                }
            }
        } else {
            struct NotSupportError: LocalizedError {
                var errorDescription: String? {
                    "PDF generation is not supported on this OS version."
                }
            }
            throw NotSupportError()
        }
    }

    private func failPDFDataRequest(for url: URL?, error: Error) {
        guard let url,
              let pdfDataRequest = pdfDataRequests[url] else {
            return
        }
        pdfDataRequest(.failure(error))
    }
}
//#endif
