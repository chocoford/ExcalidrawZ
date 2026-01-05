//
//  PDFViewerSheet.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import SwiftUI
import PDFKit

struct PDFViewerSheet: View {
    let pdfData: Data
    let fileId: String

    @Environment(\.dismiss) private var dismiss
    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header()

            Divider()

            // PDF Content
            if let pdfDocument = pdfDocument {
                PDFViewRepresentable(document: pdfDocument, currentPage: $currentPage)
            } else {
                if #available(iOS 18.0, macOS 15.0, *) {
                    ContentUnavailableView(
                        .localizable(.pdfViewerSheetFailTitle),
                        systemSymbol: .richtextPageFill,
                        description: Text(localizable: .pdfViewerSheetFailMessage)
                    )
                } else if #available(iOS 17.0, macOS 14.0, *) {
                    ContentUnavailableView(
                        .localizable(.pdfViewerSheetFailTitle),
                        systemSymbol: .docRichtextFill,
                        description: Text(localizable: .pdfViewerSheetFailMessage)
                    )
                } else {
                    VStack {
                        Text(localizable: .pdfViewerSheetFailTitle)
                    }
                }
            }
        }
        .onAppear {
            loadPDF()
        }
    }

    @ViewBuilder
    private func header() -> some View {
        HStack {
            Text(localizable: .pdfViewerSheetTitle)
                .font(.headline)

            Spacer()

            if totalPages > 0 {
                HStack(spacing: 12) {
                    // Previous page button
                    Button {
                        goToPreviousPage()
                    } label: {
                        Image(systemSymbol: .chevronLeft)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage <= 0)

                    // Page indicator
                    if #available(iOS 17.0, macOS 14.0, *) {
                        Text(localizable: .pdfViewerSheetPageIndicator(currentPage + 1, totalPages))
                            .contentTransition(.numericText(value: Double(currentPage + 1)))
                            .contentTransition(.numericText(value: Double(totalPages)))
                            .animation(.smooth, value: currentPage)
                            .animation(.smooth, value: totalPages)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text(localizable: .pdfViewerSheetPageIndicator(currentPage + 1, totalPages))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Next page button
                    Button {
                        goToNextPage()
                    } label: {
                        Image(systemSymbol: .chevronRight)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage >= totalPages - 1)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
#if os(macOS)
                Image(systemSymbol: .xmarkCircleFill)
                    .font(.title2)
                    .foregroundStyle(.secondary)
#else
                Text(localizable: .generalButtonDone)
#endif
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func loadPDF() {
        pdfDocument = PDFDocument(data: pdfData)
        totalPages = pdfDocument?.pageCount ?? 0
    }

    private func goToPreviousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    private func goToNextPage() {
        guard currentPage < totalPages - 1 else { return }
        currentPage += 1
    }
}

// MARK: - PDF View Representable

#if os(macOS)
struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical

        // Add page change notification
        NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak pdfView] _ in
            guard let pdfView = pdfView,
                  let currentPDFPage = pdfView.currentPage else { return }
            let index = document.index(for: currentPDFPage)
            if index != currentPage {
                currentPage = index
            }
        }

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Update current page when binding changes
        guard let page = document.page(at: currentPage),
              nsView.currentPage != page else { return }
        nsView.go(to: page)
    }
}
#elseif os(iOS)
struct PDFViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical

        // Add page change notification
        NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak pdfView] _ in
            guard let pdfView = pdfView,
                  let currentPDFPage = pdfView.currentPage else { return }
            let index = document.index(for: currentPDFPage)
            if index != currentPage {
                currentPage = index
            }
        }

        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Update current page when binding changes
        guard let page = document.page(at: currentPage),
              uiView.currentPage != page else { return }
        uiView.go(to: page)
    }
}
#endif

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    // Create a sample PDF for preview
    let samplePDFData = {
        let pdfDocument = PDFDocument()
        return pdfDocument.dataRepresentation() ?? Data()
    }()

    PDFViewerSheet(
        pdfData: samplePDFData,
        fileId: "preview-pdf"
    )
}
    
