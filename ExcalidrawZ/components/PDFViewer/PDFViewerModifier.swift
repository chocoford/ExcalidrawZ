//
//  PDFViewerModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import SwiftUI

extension Notification.Name {
    static let openPDFViewer = Notification.Name("openPDFViewer")
}

struct PDFViewerModifier: ViewModifier {
    @State private var viewerInfo: PDFViewerInfo?

    func body(content: Content) -> some View {
        content
            .sheet(item: $viewerInfo) { info in
                PDFViewerSheet(
                    pdfData: info.pdfData,
                    fileId: info.fileId
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPDFViewer)) { notification in
                if let info = notification.object as? PDFViewerInfo {
                    viewerInfo = info
                }
            }
    }
}

extension View {
    func pdfViewer() -> some View {
        self.modifier(PDFViewerModifier())
    }
}
