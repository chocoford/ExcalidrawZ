import SwiftUI
import ChocofordUI

struct NativeFileDropSheet: View {
    @Environment(FileState.self) private var fileState
    @Environment(\.dismiss) private var dismiss

    let session: NativeFileDropSession
    let coordinator: ExcalidrawCore
    let replacementTargetName: (DroppedDrawing) -> String?
    let onReplace: (@MainActor (DroppedDrawing) async throws -> Void)?

    var body: some View {
        ZStack {
            content
        }
        .onDisappear {
            coordinator.dismissNativeFileDrop(session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.content {
            case .reading:
                readingContent
            case .drawing(let drawing):
                DroppedDrawingImportSheet(
                    drawing: drawing,
                    coordinator: coordinator,
                    replacementTargetName: replacementTargetName(drawing),
                    onReplace: {
                        try requireCurrentDrop()
                        guard let onReplace else { throw DroppedDrawing.ImportError.replacementUnavailable }
                        try await onReplace(drawing)
                    },
                    onImport: {
                        try requireCurrentDrop()
                        try await fileState.importFile(drawing.file)
                    },
                    onCancel: cancelDrop
                )
            case .pdf(let pdf):
                PDFInsertSheet(pdfInfo: pdf, onCancel: cancelDrop) { data, mode, direction, itemsPerLine in
                    try requireCurrentDrop()
                    try await coordinator.insertPDF(
                        data, mode: mode, direction: direction, itemsPerLine: itemsPerLine,
                        sceneX: pdf.sceneX, sceneY: pdf.sceneY
                    )
                }
            case .library(let library):
                ExcalidrawLibraryImportSheetView(
                    libraries: [library],
                    validateBeforeImport: requireCurrentDrop,
                    onCancel: cancelDrop
                )
#if os(macOS)
                    .frame(minWidth: 700)
#endif
        }
    }

    private var readingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    cancelDrop()
                    dismiss()
                } label: {
                    Label(.localizable(.generalButtonCancel), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .modernButtonStyle(style: .glass, size: .large, shape: .circle)
                .keyboardShortcut(.cancelAction)

                Text(localizable: .nativeFileDropReadingTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(Array(session.files.prefix(3).enumerated()), id: \.offset) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.element.fileName)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(entry.element.fileSize.formatted(.byteCount(style: .file)))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            if session.files.count > 3 {
                Text(localizable: .nativeFileDropMoreFiles(session.files.count - 3))
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .progressViewStyle(.linear)
                .accessibilityLabel(Text(localizable: .nativeFileDropReadingTitle))
        }
        .padding(24)
#if os(macOS)
        .frame(width: 560)
#endif
    }

    private func requireCurrentDrop() throws {
        guard coordinator.isCurrentNativeFileDrop(session) else { throw NativeFileDropError.targetChanged }
    }

    private func cancelDrop() {
        coordinator.cancelNativeFileDrop(session)
    }
}
