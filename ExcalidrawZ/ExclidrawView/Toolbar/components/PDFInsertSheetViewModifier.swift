//
//  PDFInsertSheetViewModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import SwiftUI

struct PDFInsertSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var toolState: ToolState

    @Binding var isPresented: Bool

    @State private var sheetItem: PDFDropInfo?

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheetItem) { item in
                PDFInsertSheet(
                    pdfInfo: item,
                    onInsert: { pdfData, mode, direction, itemsPerLine in
                        try await handlePDFInsert(
                            pdfData: pdfData,
                            mode: mode,
                            direction: direction,
                            itemsPerLine: itemsPerLine,
                            sceneX: item.sceneX,
                            sceneY: item.sceneY
                        )
                    }
                )
            }
            .sheet(isPresented: $isPresented) {
                PDFInsertSheet(
                    onInsert: { pdfData, mode, direction, itemsPerLine in
                        try await handlePDFInsert(
                            pdfData: pdfData,
                            mode: mode,
                            direction: direction,
                            itemsPerLine: itemsPerLine,
                            sceneX: 0,
                            sceneY: 0
                        )
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPDFInsertSheet)) { notification in
                if let dropInfo = notification.object as? PDFDropInfo {
                    self.sheetItem = dropInfo
                }
            }
            .onChange(of: isPresented) { newValue in
                if !newValue {
                    sheetItem = nil
                } else {
                    sheetItem
                }
            }
    }

    private func handlePDFInsert(
        pdfData: Data,
        mode: PDFInsertMode,
        direction: String,
        itemsPerLine: Int?,
        sceneX: Double?,
        sceneY: Double?
    ) async throws {
        switch mode {
        case .viewer:
            // Insert as PDF viewer element
            let fileId = try await toolState.excalidrawWebCoordinator?.loadPDF(
                pdfData: pdfData,
                x: sceneX ?? 100,
                y: sceneY ?? 100,
                width: 600,
                height: 800
            )
            print("PDF loaded with fileId: \(fileId ?? "nil")")

        case .tiled:
            // Insert as tiled images with user-configured layout
            let fileIds = try await toolState.excalidrawWebCoordinator?.loadPDFAsTiledImages(
                pdfData: pdfData,
                imageWidth: 400,
                direction: direction,
                itemsPerLine: itemsPerLine
            )
            print("PDF loaded as tiled images with \(fileIds?.count ?? 0) pages")
        }
    }
}
