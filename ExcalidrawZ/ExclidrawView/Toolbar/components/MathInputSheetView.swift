//
//  MathInputSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import os.log

import ChocofordUI
import MathJaxSwift

struct MathInputSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MathInputSheetView { svg in
                    guard let data = svg.data(using: .utf8) else { return }
                    Task {
                        do {
                            try await fileState.excalidrawWebCoordinator?.loadImageToExcalidrawCanvas(
                                imageData: data,
                                type: "svg+xml"
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .swiftyAlert(logs: true)
            }
    }
}

struct MathInputSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MathInputSheetView")
    
    var onInsert: (_ svg: String) -> Void
    
    @State private var inputText = ""
    
    @State private var svgContent: String?
    @State private var previewSVGURL: URL?
    
    @State private var error: Error?
    
    var body: some View {
        VStack {
            HStack {
                Text("Insert Math")
                    .font(.title.italic())
                Spacer()
            }
            
            TextField("", text: $inputText).labelsHidden()
            
            Color.clear.frame(height: 100)
                .overlay {
                    if let error {
                        ZStack {
                            if case let error as LocalizedError = error {
                                Text(error.errorDescription ?? error.localizedDescription)
                            } else if let error = error as (any CustomStringConvertible)? {
                                Text(error.description)
                            } else {
                                Text(error.localizedDescription)
                            }
                        }
                        .foregroundStyle(.red)
                    } else if let previewSVGURL {
                        SVGPreviewView(svgURL: previewSVGURL)
                    } else {
                        Text("Preview here")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            
            Divider()
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                Button {
                    if let svgContent {
                        onInsert(svgContent)
                        dismiss()
                    }
                } label: {
                    Text("Insert")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onChange(of: inputText, debounce: 0.2) { newValue in
            generatePreview(input: newValue)
        }
    }
    
    private func generatePreview(input: String) {
        logger.debug("[MathInputSheetView] generatePreview for \(input)")
        self.error = nil
        do {
            let mathjax = try MathJax()
            let svg = try mathjax.tex2svg(input)
            let tempDir = FileManager.default.temporaryDirectory
            let svgFilename = "\(UUID()).svg"
            
            let svgURL = tempDir.appendingPathComponent(svgFilename, conformingTo: .svg)
            try svg.data(using: .utf8)?.write(to: svgURL)
            
            self.svgContent = svg
            self.previewSVGURL = svgURL
        }
        catch {
            logger.error("[MathInputSheetView] error: \(error)")
            self.error = error
        }
    }
}

#Preview {
    MathInputSheetView() { _ in
        
    }
}
