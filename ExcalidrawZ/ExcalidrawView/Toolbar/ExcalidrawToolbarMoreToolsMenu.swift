//
//  ExcalidrawToolbarMoreToolsMenu.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

import SwiftUI

import SFSafeSymbols

struct ExcalidrawToolbarMoreToolsMenu: View {
    @Environment(ToolState.self) private var toolState

    @State private var isMathInputSheetPresented = false
    @State private var isMermaidInputSheetPresented = false
    @State private var isPDFPickerPresented = false

    var body: some View {
        Menu {
#if DEBUG
#if !os(iOS)
            Button {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .text2Diagram)
                }
            } label: {
                Text(.localizable(.toolbarText2Diagram))
            }
#endif
#endif
            Button {
                isMermaidInputSheetPresented.toggle()
            } label: {
                Text(.localizable(.toolbarMermaid))
            }

            Button {
                isMathInputSheetPresented.toggle()
            } label: {
                Text(.localizable(.toolbarLatexMath))
            }

            Button {
                isPDFPickerPresented.toggle()
            } label: {
                Text(localizable: .toolbarInsertPDF)
            }
        } label: {
            if #available(macOS 15.0, iOS 18.0, *) {
                Label(.localizable(.toolbarMoreTools), systemImage: "xmark.triangle.circle.square")
            } else if #available(macOS 13.0, iOS 16.0, *) {
                Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
            } else {
                Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
            }
        }
        .menuIndicator(.hidden)
#if os(iOS)
        .menuOrder(.fixed)
#endif
        .modifier(MermaidInputSheetViewModifier(isPresented: $isMermaidInputSheetPresented))
        .modifier(MathInputSheetViewModifier(isPresented: $isMathInputSheetPresented))
        .modifier(PDFInsertSheetViewModifier(isPresented: $isPDFPickerPresented))
    }
}
