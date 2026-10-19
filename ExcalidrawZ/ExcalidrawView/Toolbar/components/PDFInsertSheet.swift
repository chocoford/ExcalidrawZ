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
import ChocofordUI

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
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var pdfInfo: PDFDropInfo?
    var onInsert: (Data, PDFInsertMode, String, Int?) async throws -> Void
    
    @State private var selectedMode: PDFInsertMode = .viewer
    @State private var isFilePickerPresented = false
    @State private var fileName: String?
    @State private var pdfData: Data?

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
        sheetContent
        .safeAreaInset(edge: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background)
                    .accessibilityIdentifier("pdfInsert.error")
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .watch(value: pdfInfo, initial: true) { _, pdfInfo in
            // Load preloaded PDF data if available
            if let pdfData = pdfInfo?.pdfData {
#if canImport(PDFKit)
                self.pdfDocument = PDFDocument(data: pdfData)
                self.fileName = pdfInfo?.fileName
#endif
                self.pdfData = pdfData
            } else {
                self.fileName = nil
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
#if os(iOS)
        NavigationStack {
            SwiftUI.Group {
                if usesCompactLayout {
                    compactSheetContent
                } else {
                    regularSheetContent
                }
            }
            .navigationTitle(.localizable(.insertPDFSheetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: pdfInsertToolbar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#else
        regularSheetContent
            .navigationTitle(.localizable(.insertPDFSheetTitle))
            .toolbar(content: pdfInsertToolbar)
#endif
    }

    private var usesCompactLayout: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
#else
        false
#endif
    }

    @ViewBuilder
    private var regularSheetContent: some View {
        HStack(spacing: 0) {
            // Keep settings reachable when the sheet is short or text is large.
            ScrollView {
                regularSettings
            }
            .frame(width: 300)
            .padding()

            Divider()

            regularPreview
        }
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
    }

    private var regularSettings: some View {
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
                        .modernButtonStyle(style: .glass, shape: .modern)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(999)
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
                                    .fixedSize(horizontal: false, vertical: true)
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
                    .accessibilityIdentifier("pdfInsert.mode.\(mode.rawValue)")
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
                                .accessibilityLabel(Text(localizable: direction == .vertical ? .insertPDFSheetItemsPerRow : .insertPDFSheetItemsPerColumn))
                                .accessibilityIdentifier("pdfInsert.itemsPerLine")
                        }
                        .labelsHidden()
                    }

                }
            }

        }
    }

    private var regularPreview: some View {
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

    @ViewBuilder
    private var compactSheetContent: some View {
#if os(iOS)
        Form {
            Section {
                compactFileSelectionRow
            } header: {
                Text(localizable: .insertPDFSheetPDFFileLabel)
            }

            Section {
                ForEach(PDFInsertMode.allCases, id: \.self) { mode in
                    compactModeRow(mode)
                }
            } header: {
                Text(localizable: .insertPDFSheetDisplayModeLabel)
            }

            if selectedMode == .tiled {
                Section {
                    Picker(selection: $direction) {
                        Text(localizable: .insertPDFSheetDirectionVertical).tag(TilesDiection.vertical)
                        Text(localizable: .insertPDFSheetDirectionHorizontal).tag(TilesDiection.horizontal)
                    } label: {
                        Text(localizable: .insertPDFSheetLayoutOptionsLabel)
                    }
                    .pickerStyle(.menu)

                    Stepper(value: $itemsPerLine, in: 1...10) {
                        HStack {
                            Text(localizable: direction == .vertical ? .insertPDFSheetItemsPerRow : .insertPDFSheetItemsPerColumn)
                            Spacer()
                            Text("\(itemsPerLine)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(localizable: .insertPDFSheetOptionsLabel)
                }
            }

            Section {
                compactPreviewContent
            } header: {
                Text(localizable: .insertPDFSheetPreviewLabel)
            }

        }
        .formStyle(.grouped)
#else
        regularSheetContent
#endif
    }

    @ToolbarContentBuilder
    private func pdfInsertToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text(.localizable(.generalButtonCancel))
            }
            .modernButtonStyle(style: .glass, shape: .modern)
            .accessibilityIdentifier("pdfInsert.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                insertPDF()
            } label: {
                Text(.localizable(.insertPDFSheetButtonInsert))
            }
            .modernButtonStyle(style: .glassProminent, shape: .modern)
            .disabled(pdfData == nil || isLoading)
            .accessibilityIdentifier("pdfInsert.confirm")
        }
    }

    @ViewBuilder
    private var compactFileSelectionRow: some View {
        if let fileName {
            HStack(spacing: 12) {
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
            }
        } else {
            Button {
                isFilePickerPresented = true
            } label: {
                Label(.localizable(.insertPDFSheetSelectPDFFileLabel), systemSymbol: .docBadgePlus)
            }
        }
    }

    @ViewBuilder
    private func compactModeRow(_ mode: PDFInsertMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemSymbol: selectedMode == mode ? .checkmarkCircleFill : .circle)
                    .foregroundStyle(selectedMode == mode ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pdfInsert.mode.\(mode.rawValue)")
    }

    @ViewBuilder
    private var compactPreviewContent: some View {
        if pdfData == nil {
            VStack(spacing: 12) {
                if #available(macOS 15.0, iOS 18.0, *) {
                    Image(systemSymbol: .textRectanglePage)
                        .font(.system(size: 44))
                        .foregroundColor(.gray)
                } else {
                    Image(systemSymbol: .docTextImage)
                        .font(.system(size: 44))
                        .foregroundColor(.gray)
                }
                Text(localizable: .insertPDFSheetSelectPrompt)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            compactPDFPreviewContent
        }
    }

    @ViewBuilder
    private var compactPDFPreviewContent: some View {
#if canImport(PDFKit)
        if let pdfDocument {
            switch selectedMode {
                case .viewer:
                    compactViewerPreview(pdfDocument)
                case .tiled:
                    compactTiledPreview(pdfDocument)
            }
        }
#else
        Text(localizable: .insertPDFSheetNoPreview)
            .foregroundColor(.secondary)
#endif
    }

#if canImport(PDFKit)
    @ViewBuilder
    private func compactViewerPreview(_ pdfDocument: PDFDocument) -> some View {
        VStack(spacing: 16) {
            ForEach(0..<pdfDocument.pageCount, id: \.self) { pageIndex in
                if let page = pdfDocument.page(at: pageIndex) {
                    PDFPageView(page: page)
                        .aspectRatio(
                            page.bounds(for: .mediaBox).size.width / page.bounds(for: .mediaBox).size.height,
                            contentMode: .fit
                        )
                        .frame(maxWidth: .infinity)
                        .shadow(radius: 2)
                }
            }

            if pdfDocument.pageCount > 1 {
                Text(localizable: .insertPDFSheetPagesCount(pdfDocument.pageCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func compactTiledPreview(_ pdfDocument: PDFDocument) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: compactTiledPreviewColumnCount
        )

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<pdfDocument.pageCount, id: \.self) { pageIndex in
                pagePreviewItem(page: pdfDocument.page(at: pageIndex), pageNumber: pageIndex + 1)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var compactTiledPreviewColumnCount: Int {
        min(max(itemsPerLine, 1), 3)
    }
#endif

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
                VStack(spacing: 20) {
                    ForEach(0..<pdfDocument.pageCount, id: \.self) { i in
                        if let page = pdfDocument.page(at: i) {
                            PDFPageView(page: page)
                                .aspectRatio(
                                    page.bounds(for: .mediaBox).size.width / page.bounds(for: .mediaBox).size.height,
                                    contentMode: .fit
                                )
                                .frame(maxWidth: 400)
                                .shadow(radius: 4)
                        }
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
        guard let pdfData, !isLoading else { return }
        
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
        onInsert: { _, _, _, _ in },
    )
}
