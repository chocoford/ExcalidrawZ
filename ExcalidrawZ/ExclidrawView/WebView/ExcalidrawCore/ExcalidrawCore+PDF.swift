//
//  ExcalidrawCore+PDF.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/17.
//

import Foundation
import WebKit

#if canImport(PDFKit)
import PDFKit
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ExcalidrawCore {
    /// Load PDF file into Excalidraw canvas
    /// - Parameters:
    ///   - pdfData: PDF file data (will be converted to ArrayBuffer)
    ///   - x: X position on canvas (default: 0)
    ///   - y: Y position on canvas (default: 0)
    ///   - width: PDF viewer width (default: 600)
    ///   - height: PDF viewer height (default: 800)
    ///   - totalPages: Total page count (optional, will auto-detect from PDF if not provided)
    /// - Returns: File ID of the inserted PDF
    @MainActor
    func loadPDF(
        pdfData: Data,
        x: Double = 0,
        y: Double = 0,
        width: Double = 600,
        height: Double = 800,
        totalPages: Int? = nil
    ) async throws -> String {
        var buffer = [UInt8](repeating: 0, count: pdfData.count)
        pdfData.copyBytes(to: &buffer, count: pdfData.count)
        let buf = buffer

        // Get page count from PDF if not provided
        let pageCount: Int
        if let providedPages = totalPages {
            pageCount = providedPages
        } else {
            #if canImport(PDFKit)
            if let pdfDocument = PDFDocument(data: pdfData) {
                pageCount = pdfDocument.pageCount
            } else {
                pageCount = 1 // Fallback if PDF parsing fails
            }
            #else
            pageCount = 1 // Fallback for platforms without PDFKit
            #endif
        }

        let result = try await webView.evaluateJavaScript("""
            (async () => {
                const bytes = new Uint8Array(\(buf));
                await window.excalidrawZHelper.loadPDFViewer(bytes.buffer, {
                    x: \(x),
                    y: \(y),
                    width: \(width),
                    height: \(height),
                    totalPages: \(pageCount)
                });
            })();
            0;
        """)

        return result as? String ?? ""
    }

    /// Load PDF as tiled images on Excalidraw canvas
    /// - Parameters:
    ///   - pdfData: PDF file data
    ///   - imageWidth: Width of each page image (default: 400)
    ///   - direction: Layout direction - "vertical" or "horizontal" (default: "vertical")
    ///   - itemsPerLine: Number of items per row/column before wrapping (default: nil for unlimited)
    /// - Returns: Array of image file IDs
    @MainActor
    func loadPDFAsTiledImages(
        pdfData: Data,
        imageWidth: Double = 400,
        direction: String = "vertical",
        itemsPerLine: Int? = nil
    ) async throws -> [String] {
        #if canImport(PDFKit)
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw NSError(domain: "ExcalidrawCore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF document"])
        }

        let pageCount = pdfDocument.pageCount
        var imageDataArray: [[String: Any]] = []

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            // Get page bounds
            let pageRect = page.bounds(for: .mediaBox)
            let aspectRatio = pageRect.width / pageRect.height
            let imageHeight = imageWidth / aspectRatio

            // Render page to image at 2x for better quality
            let renderSize = CGSize(width: imageWidth * 2, height: imageHeight * 2)
            #if os(macOS)
            let image = NSImage(size: renderSize)
            image.lockFocus()

            // Scale to fill the render size
            if let context = NSGraphicsContext.current?.cgContext {
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: renderSize))

                let scaleFactor = min(renderSize.width / pageRect.width, renderSize.height / pageRect.height)
                context.scaleBy(x: scaleFactor, y: scaleFactor)
                context.interpolationQuality = .high

                page.draw(with: .mediaBox, to: context)
            }

            image.unlockFocus()

            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let imageData = bitmapImage.representation(using: .png, properties: [:]) else {
                continue
            }
            #else
            let renderer = UIGraphicsImageRenderer(size: renderSize)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: renderSize))

                // Scale and draw PDF page
                let scaleFactor = min(renderSize.width / pageRect.width, renderSize.height / pageRect.height)
                context.cgContext.scaleBy(x: scaleFactor, y: scaleFactor)
                page.draw(with: .mediaBox, to: context.cgContext)
            }

            guard let imageData = image.pngData() else {
                continue
            }
            #endif

            // Convert to base64
            let base64String = imageData.base64EncodedString()

            // Add to array with metadata
            imageDataArray.append([
                "imageData": "data:image/png;base64,\(base64String)",
                "width": imageWidth,
                "height": imageHeight
            ])
        }

        // Convert array to JSON string
        guard let jsonData = try? JSONSerialization.data(withJSONObject: imageDataArray, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "ExcalidrawCore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize image data"])
        }

        // Build options object
        var options = "{ direction: \"\(direction)\""
        if let itemsPerLine {
            options += ", itemsPerLine: \(itemsPerLine)"
        }
        options += " }"

        // Call JavaScript once with all images
        let result = try await webView.evaluateJavaScript("""
            (async () => {
                const pages = \(jsonString);
                const fileIds = await window.excalidrawZHelper.loadPDFTiles(pages, \(options));
                return fileIds;
            })();
            0;
        """)

        if let fileIds = result as? [String] {
            return fileIds
        }
        return []
        #else
        throw NSError(domain: "ExcalidrawCore", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDFKit not available on this platform"])
        #endif
    }
}
