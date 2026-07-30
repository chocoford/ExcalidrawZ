#if os(macOS)
import AppKit
import Foundation
import WebKit

@MainActor
enum ScreenAnnotationDocumentBridge {
    enum Mode: String {
        case raw
        case bitmap
    }

    static func makeDocument(
        in webView: WKWebView,
        imageData: Data,
        imageFormat: ScreenAnnotationSaveFormat,
        mode: Mode,
        viewportRect: CGRect,
        selectionRect: CGRect?
    ) async throws -> ExcalidrawFile {
        guard let bitmap = NSBitmapImageRep(data: imageData) else {
            throw ScreenAnnotationSaveService.SaveError.imageUnavailable
        }

        let dataURL =
            "data:\(imageFormat.mimeType);base64,\(imageData.base64EncodedString())"
        let rawDocument = try await webView.callAsyncJavaScript(
            """
            const helper = window.excalidrawZHelper;
            if (typeof helper?.createScreenAnnotationDocument !== "function") {
              throw new Error(
                "Screen annotation document API is unavailable."
              );
            }

            const options = {
              mode,
              image: {
                dataURL,
                mimeType,
                width: imagePixelWidth,
                height: imagePixelHeight,
                created,
              },
              viewportRect: {
                x: viewportX,
                y: viewportY,
                width: viewportWidth,
                height: viewportHeight,
              },
            };
            if (hasSelection) {
              options.selectionRect = {
                x: selectionX,
                y: selectionY,
                width: selectionWidth,
                height: selectionHeight,
              };
            }
            return JSON.stringify(
              helper.createScreenAnnotationDocument(options)
            );
            """,
            arguments: [
                "mode": mode.rawValue,
                "dataURL": dataURL,
                "mimeType": imageFormat.mimeType,
                "imagePixelWidth": bitmap.pixelsWide,
                "imagePixelHeight": bitmap.pixelsHigh,
                "created": Int(Date().timeIntervalSince1970 * 1_000),
                "viewportX": viewportRect.minX,
                "viewportY": viewportRect.minY,
                "viewportWidth": max(viewportRect.width, 1),
                "viewportHeight": max(viewportRect.height, 1),
                "hasSelection": selectionRect != nil,
                "selectionX": selectionRect?.minX ?? 0,
                "selectionY": selectionRect?.minY ?? 0,
                "selectionWidth": max(selectionRect?.width ?? 1, 1),
                "selectionHeight": max(selectionRect?.height ?? 1, 1),
            ],
            contentWorld: .page
        )
        guard let documentJSON = rawDocument as? String,
              let documentData = documentJSON.data(using: .utf8) else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }
        return try ExcalidrawFile(data: documentData)
    }

    static func insert(
        _ document: ExcalidrawFile,
        into webView: WKWebView
    ) async throws {
        guard let documentData = document.content,
              let documentJSON = String(
                data: documentData,
                encoding: .utf8
              ) else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        _ = try await webView.callAsyncJavaScript(
            """
            const helper = window.excalidrawZHelper;
            if (typeof helper?.insertScreenAnnotationDocument !== "function") {
              throw new Error(
                "Screen annotation insertion API is unavailable."
              );
            }

            return helper.insertScreenAnnotationDocument(
              JSON.parse(documentJSON),
              {
                columns: 4,
                gap: 40,
                focus: {
                  mode: "center",
                  animate: false,
                },
                captureUpdate: "IMMEDIATELY",
              }
            );
            """,
            arguments: ["documentJSON": documentJSON],
            contentWorld: .page
        )
    }
}
#endif
