//
//  PDFInsertSheetViewModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import SwiftUI

struct PDFInsertSheetViewModifier: ViewModifier {
    @Environment(ToolState.self) private var toolState

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                PDFInsertSheet { pdfData, mode, direction, itemsPerLine in
                    guard let coordinator = toolState.excalidrawWebCoordinator else {
                        throw NativeFileDropError.targetChanged
                    }
                    try await coordinator.insertPDF(
                        pdfData, mode: mode, direction: direction, itemsPerLine: itemsPerLine,
                        sceneX: 0, sceneY: 0
                    )
                }
            }
    }
}
