import SwiftUI
import ChocofordUI

struct DroppedDrawingImportSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let drawing: DroppedDrawing
    let coordinator: ExcalidrawCore
    let replacementTargetName: String?
    let onReplace: @MainActor () async throws -> Void
    let onImport: @MainActor () async throws -> Void
    var onCancel: (() -> Void)? = nil

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var preview: Preview = .loading

    private enum Preview {
        case loading
        case rendered(ExcalidrawCore.DrawingPreview)
        case unavailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                cancelButton
                Text(localizable: .drawingDropTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            Text(drawing.fileName)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            drawingPreview

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    replaceButton
                    importButton
                }
                VStack(alignment: .trailing, spacing: 12) {
                    importButton
                    replaceButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .controlSize(.large)
            .disabled(isWorking)
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
#if os(macOS)
        .frame(width: 560)
#endif
        .task(id: colorScheme) {
            await renderPreview()
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var drawingPreview: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 240)
            .overlay {
                if case .rendered(let result) = preview {
                    Image(platformImage: result.background)
                        .resizable()
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                switch preview {
                    case .loading:
                        ProgressView()
                            .accessibilityLabel(Text(localizable: .generalLoading))
                    case .rendered(let result):
                        if let image = result.drawing {
                            Image(platformImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                                .accessibilityLabel(Text(localizable: .drawingDropPreview))
                        } else {
                            Text(localizable: .drawingDropPreviewEmpty)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: .capsule)
                        }
                    case .unavailable:
                        Text(localizable: .drawingDropPreviewUnavailable)
                            .foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }

    private func renderPreview() async {
        guard let sceneData = drawing.file.content else {
            preview = .unavailable
            return
        }

        preview = .loading
        do {
            let result = try await coordinator.exportDrawingPreview(
                sceneData: sceneData,
                colorScheme: colorScheme
            )
            try Task.checkCancellation()
            preview = .rendered(result)
        } catch {
            guard !Task.isCancelled else { return }
            coordinator.logger.debug("Failed to render drawing drop preview: \(error)")
            preview = .unavailable
        }
    }

    private var description: String {
        if let replacementTargetName {
            String(localizable: .drawingDropDescription(replacementTargetName))
        } else {
            String(localizable: .drawingDropImportOnlyDescription)
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
            onCancel?()
            dismiss()
        } label: {
            Label(.localizable(.generalButtonCancel), systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .modernButtonStyle(style: .glass, size: .large, shape: .circle)
        .keyboardShortcut(.cancelAction)
        .disabled(isWorking)
    }

    private var replaceButton: some View {
        Button(.localizable(.drawingDropReplace), role: .destructive) {
            perform(onReplace)
        }
        .buttonStyle(.bordered)
        .disabled(replacementTargetName == nil)
    }

    private var importButton: some View {
        Button(.localizable(.drawingDropImportNew)) {
            perform(onImport)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
