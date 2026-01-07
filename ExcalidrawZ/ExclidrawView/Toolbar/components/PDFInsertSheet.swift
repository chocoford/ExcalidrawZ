//
//  PDFInsertSheet.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/19.
//

import SwiftUI

#if canImport(PDFKit)
import PDFKit
#endif

import SFSafeSymbols

enum PDFInsertMode: String, CaseIterable {
    case viewer
    case tiled
    
    var title: LocalizedStringKey {
        switch self {
            case .viewer:
                return .localizable(.insertPDFSheetModeViewerTitle)
            case .tiled:
                return .localizable(.insertPDFSheetModeTiledTitle)
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
            case .viewer:
                return .localizable(.insertPDFSheetModeViewerDescription)
            case .tiled:
                return .localizable(.insertPDFSheetModeTiledDescription)
        }
    }
}

struct PDFInsertSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var isPresented: Bool
    var onInsert: (Data, PDFInsertMode, String, Int?) async throws -> Void
    
    @Binding var pdfData: Data?
    @Binding var fileName: String?
    
    @State private var selectedMode: PDFInsertMode = .viewer
    @State private var isFilePickerPresented = false
    
    // Tiled mode options
    enum TilesDiection: String {
        case vertical
        case horizontal
    }
    @State private var direction: TilesDiection = .vertical
    @State private var itemsPerLine: Int = 1
    
#if canImport(PDFKit)
    @State private var pdfDocument: PDFDocument?
#endif
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: Settings
            VStack(alignment: .leading, spacing: 20) {
                // File Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizable: .insertPDFSheetPDFFileLabel)
                        .font(.headline)
                    
                    if let fileName = fileName {
                        HStack {
                            Image(systemSymbol: .docFill)
                                .foregroundStyle(.red)
                            Text(fileName)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                isFilePickerPresented = true
                            } label: {
                                Text(.localizable(.insertPDFSheetButtonChange))
                            }
                            .modernButtonStyle(style: .glass)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Button {
                            isFilePickerPresented = true
                        } label: {
                            Label {
                                Text(.localizable(.insertPDFSheetSelectPDFFileLabel))
                            } icon: {
                                Image(systemSymbol: .docBadgePlus)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .modernButtonStyle(style: .glassProminent, size: .regular, shape: .capsule)
                        .controlSize(.large)
                    }
                }
                
                Divider()
                
                // Mode Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizable: .insertPDFSheetDisplayModeLabel)
                        .font(.headline)
                    
                    ForEach(PDFInsertMode.allCases, id: \.self) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                
                                Image(systemSymbol: selectedMode == mode ? .checkmarkCircleFill : .circle)
                                    .foregroundStyle(selectedMode == mode ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background {
                                Capsule()
                                    .fill(selectedMode == mode ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
                            .overlay(
                                Capsule()
                                    .stroke(selectedMode == mode ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Tiled mode options
                if selectedMode == .tiled {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localizable: .insertPDFSheetOptionsLabel)
                            .font(.headline)
                        
                        HStack {
                            Text(localizable: .insertPDFSheetLayoutOptionsLabel)
                            
                            Spacer(minLength: 0)
                            
                            Picker("Direction", selection: $direction) {
                                Text(localizable: .insertPDFSheetDirectionVertical).tag(TilesDiection.vertical)
                                Text(localizable: .insertPDFSheetDirectionHorizontal).tag(TilesDiection.horizontal)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .modernButtonStyle(style: .glass, shape: .capsule)
                        }
                        
                        // Items per line
                        HStack {
                            Text(localizable: direction == .vertical ? .insertPDFSheetItemsPerRow : .insertPDFSheetItemsPerColumn)
                            Spacer(minLength: 0)
                            HStack {
                                TextField("", value: $itemsPerLine, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 48)
                                Stepper("", value: $itemsPerLine, in: 1...10)
                            }
                            .labelsHidden()
                        }
                        
                        Spacer()
                        
                    }
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                
                Spacer()
            }
            .frame(width: 300)
            .padding()
            
            Divider()
            
            // Right side: Preview
            VStack {
                Text(localizable: .insertPDFSheetPreviewLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top)
                
                if pdfData == nil {
                    VStack(spacing: 16) {
                        if #available(macOS 15.0, iOS 18.0, *) {
                            Image(systemSymbol: .textRectanglePage)
                                .font(.system(size: 64))
                                .foregroundColor(.gray)
                        } else {
                            Image(systemSymbol: .docTextImage)
                                .font(.system(size: 64))
                                .foregroundColor(.gray)
                        }
                        Text(localizable: .insertPDFSheetSelectPrompt)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    previewContent()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.05))
        }
        .navigationTitle(.localizable(.insertPDFSheetTitle))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
                .modernButtonStyle(style: .glass, shape: .modern)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    insertPDF()
                } label: {
                    Text(.localizable(.insertPDFSheetButtonInsert))
                }
                .modernButtonStyle(style: .glassProminent, shape: .modern)
                .disabled(pdfData == nil || isLoading)
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
        .onAppear {
            // Load preloaded PDF data if available
            if let pdfData = pdfData {
#if canImport(PDFKit)
                pdfDocument = PDFDocument(data: pdfData)
#endif
                self.pdfData = nil
            } else {
                self.fileName = nil
            }
        }
    }
    
    @ViewBuilder
    private func previewContent() -> some View {
        switch selectedMode {
            case .viewer:
                viewerPreview()
            case .tiled:
                tiledPreview()
        }
    }
    
    @ViewBuilder
    private func viewerPreview() -> some View {
#if canImport(PDFKit)
        if let pdfDocument {
            ScrollView {
                VStack(spacing: 0) {
                    if let firstPage = pdfDocument.page(at: 0) {
                        PDFPageView(page: firstPage)
                            .aspectRatio(firstPage.bounds(for: .mediaBox).size.width / firstPage.bounds(for: .mediaBox).size.height, contentMode: .fit)
                            .frame(maxWidth: 400)
                            .shadow(radius: 4)
                    }
                }
                .padding()
            }
            
            if pdfDocument.pageCount > 1 {
                Text(localizable: .insertPDFSheetPagesCount(pdfDocument.pageCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
#else
        Text(localizable: .insertPDFSheetNoPreview)
            .foregroundColor(.secondary)
#endif
    }
    
    @ViewBuilder
    private func tiledPreview() -> some View {
#if canImport(PDFKit)
        if let pdfDocument {
            if direction == .vertical {
                // Vertical layout: left to right, then wrap to next row
                ScrollView {
                    let columns: [GridItem] = {
                        if itemsPerLine > 0 {
                            return Array(repeating: GridItem(.flexible(), spacing: 16), count: itemsPerLine)
                        } else {
                            return [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]
                        }
                    }()
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<pdfDocument.pageCount, id: \.self) { pageIndex in
                            pagePreviewItem(page: pdfDocument.page(at: pageIndex), pageNumber: pageIndex + 1)
                        }
                    }
                    .padding()
                }
            } else {
                // Horizontal layout: top to bottom, then wrap to next column
                ScrollView(.horizontal) {
                    let rows: [GridItem] = {
                        if itemsPerLine > 0 {
                            return Array(repeating: GridItem(.flexible(), spacing: 16), count: itemsPerLine)
                        } else {
                            return [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]
                        }
                    }()
                    
                    LazyHGrid(rows: rows, spacing: 16) {
                        ForEach(0..<pdfDocument.pageCount, id: \.self) { pageIndex in
                            pagePreviewItem(page: pdfDocument.page(at: pageIndex), pageNumber: pageIndex + 1)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
            }
        }
#else
        Text(localizable: .insertPDFSheetNoPreview)
            .foregroundColor(.secondary)
#endif
    }
    
    @ViewBuilder
    private func pagePreviewItem(page: PDFPage?, pageNumber: Int) -> some View {
        if let page {
            VStack(spacing: 4) {
                PDFPageView(page: page)
                    .aspectRatio(page.bounds(for: .mediaBox).size.width / page.bounds(for: .mediaBox).size.height, contentMode: .fit)
                // .frame(maxWidth: 200)
                    .shadow(radius: 2)
                
                Text(localizable: .insertPDFSheetPageNumber(pageNumber))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            
            fileName = url.lastPathComponent
            pdfData = data
            errorMessage = nil
            
#if canImport(PDFKit)
            pdfDocument = PDFDocument(data: data)
#endif
        } catch {
            errorMessage = String(localizable: .insertPDFSheetErrorLoadFailed(error.localizedDescription))
        }
    }
    
    private func insertPDF() {
        guard let pdfData else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let itemsPerLineValue = itemsPerLine == 0 ? nil : itemsPerLine
                try await onInsert(pdfData, selectedMode, direction.rawValue, itemsPerLineValue)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localizable: .insertPDFSheetErrorLoadFailed(error.localizedDescription))
                    isLoading = false
                }
            }
        }
    }
}

#if canImport(PDFKit)
struct PDFPageView: View {
    let page: PDFPage
    
    var body: some View {
        GeometryReader { geometry in
            let image = page.thumbnail(of: geometry.size, for: .mediaBox)
#if os(macOS)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
#else
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
#endif
            
        }
    }
}
#endif

#Preview {
    PDFInsertSheet(
        isPresented: .constant(true),
        onInsert: { _, _, _, _ in },
        pdfData: .constant(nil),
        fileName: .constant(nil)
    )
}
