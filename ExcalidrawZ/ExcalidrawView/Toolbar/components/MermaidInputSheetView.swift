//
//  MermaidInputSheetView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/03.
//

import SwiftUI
import SwiftyAlert
import ChocofordUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct MermaidInputSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @EnvironmentObject private var fileState: FileState

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        let content = NavigationStack {
            MermaidInputSheetView { definition in
                try await insertMermaidDefinition(definition)
            }
        }

#if os(iOS)
        if #available(iOS 18.0, *), containerHorizontalSizeClass != .compact {
            content
                .presentationSizing(.page)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
#else
        content
#endif
    }

    @MainActor
    private func insertMermaidDefinition(_ definition: String) async throws {
        do {
            var options = ExcalidrawCore.MermaidInsertOptions()
            options.focus = .mode(.center)
            guard let coordinator = activeCoordinator else {
                throw MermaidInputSheetError.noActiveCanvas
            }
            _ = try await coordinator.insertFromMermaid(definition, options: options)
        } catch {
            alertToast(error)
            throw error
        }
    }

    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator
            default:
                fileState.excalidrawWebCoordinator
        }
    }
}

struct MermaidInputSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    var onInsert: (_ definition: String) async throws -> Void

    @State private var inputText = ""
    @State private var selectedPage: MermaidInputSheetPage = .input
    @State private var previewState: MermaidPreviewState = .idle
    @State private var previewImage: Image?
    @State private var previewTask: Task<Void, Never>?
    @State private var isInserting = false

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            sheetHeader
            content
        }
        .padding()
        .watch(value: selectedPage) { newValue in
            guard usesCompactLayout else { return }
            if newValue == .preview {
                schedulePreview()
            }
        }
        .watch(value: usesCompactLayout) { isCompact in
            handleLayoutChanged(isCompact: isCompact)
        }
        .onChange(of: trimmedInput, debounce: 0.35) { _ in
            handleInputChanged()
        }
        .onAppear {
            if !usesCompactLayout {
                schedulePreview()
            }
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var sheetHeader: some View {
        ZStack {
            Text(.localizable(.toolbarMermaid))
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 132)

            HStack {
                Button {
                    previewTask?.cancel()
                    dismiss()
                } label: {
                    Label(.localizable(.generalButtonCancel), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .modernButtonStyle(style: .glass, size: .extraLarge, shape: .circle)
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Button {
                    insertMermaid()
                } label: {
                    if isInserting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(.localizable(.librariesButtonItemAddToCanvas))
                        }
                    } else {
                        Text(.localizable(.librariesButtonItemAddToCanvas))
                    }
                }
                .lineLimit(1)
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(insertButtonDisabled)
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var content: some View {
        if usesCompactLayout {
            compactContent
        } else {
            regularContent
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker("", selection: $selectedPage) {
                    Text(.localizable(.mermaidInputSheetInputTab))
                        .tag(MermaidInputSheetPage.input)
                    Text(.localizable(.mermaidInputSheetPreviewTab))
                        .tag(MermaidInputSheetPage.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ZStack {
                switch selectedPage {
                    case .input:
                        inputEditor
                    case .preview:
                        previewContent
                }
            }
            .frame(minHeight: contentHeight)
        }
    }

    private var regularContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                inputHeader
                inputEditor
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                Text(.localizable(.mermaidInputSheetPreviewTab))
                    .font(.headline)
                previewContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
#if os(macOS)
        .frame(minWidth: 820, idealWidth: 900, minHeight: 460, idealHeight: 520)
#else
        .frame(maxWidth: .infinity)
        .frame(minHeight: 460, idealHeight: 520)
#endif
    }

    private var usesCompactLayout: Bool {
#if os(macOS)
        false
#else
        containerHorizontalSizeClass == .compact
#endif
    }

    private var insertButtonDisabled: Bool {
        trimmedInput.isEmpty ||
            isInserting ||
            !previewSucceeded
    }

    private var previewSucceeded: Bool {
        previewState == .loaded && previewImage != nil
    }

    private var inputHeader: some View {
        Text(.localizable(.mermaidInputSheetInputTab))
            .font(.headline)
    }

    private var contentHeight: CGFloat {
        #if os(iOS)
        320
        #else
        280
        #endif
    }

    private func handleInputChanged() {
        if usesCompactLayout, selectedPage != .preview {
            previewState = .idle
            previewImage = nil
            return
        }

        schedulePreview()
    }

    private func handleLayoutChanged(isCompact: Bool) {
        if isCompact, selectedPage != .preview {
            previewTask?.cancel()
            previewState = .idle
            previewImage = nil
            return
        }

        schedulePreview()
    }

    private var inputEditor: some View {
        TextArea(
            text: $inputText,
            placeholder: Text(.localizable(.mermaidInputSheetPlaceholder))
        )
            .textFont(.system(design: .monospaced))
            .textInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 72))
            .textAreaSizing(.fill)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label(.localizable(.mermaidInputSheetPasteButton), systemImage: "clipboard")
                        .labelStyle(.iconOnly)
                }
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .circle)
                .padding(12)
            }
    }

    private var previewContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)

            switch previewState {
                case .idle:
                    Text(.localizable(.mermaidInputSheetPreviewEmpty))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                case .loading:
                    ProgressView()
                        .controlSize(.regular)
                case .loaded:
                    if let previewImage {
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                    } else {
                        Text(.localizable(.mermaidInputSheetPreviewUnavailable))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                case .failed(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()

        let definition = trimmedInput
        guard !definition.isEmpty else {
            previewState = .idle
            previewImage = nil
            return
        }

        previewState = .loading
        previewTask = Task {
            guard !Task.isCancelled else { return }
            await renderPreview(definition)
        }
    }

    @MainActor
    private func renderPreview(_ definition: String) async {
        do {
            let data = try await MermaidPreviewRenderer.renderPNGData(definition)
            guard !Task.isCancelled, definition == trimmedInput else { return }
            if let image = MermaidPreviewRenderer.image(from: data) {
                previewImage = image
                previewState = .loaded
            } else {
                previewImage = nil
                previewState = .loaded
            }
        } catch {
            guard !Task.isCancelled, definition == trimmedInput else { return }
            previewImage = nil
            previewState = .failed(error.localizedDescription)
        }
    }

    private func insertMermaid() {
        let definition = trimmedInput
        guard !definition.isEmpty, !isInserting, previewSucceeded else { return }
        isInserting = true
        Task { @MainActor in
            do {
                try await onInsert(definition)
                previewTask?.cancel()
                dismiss()
            } catch {
                isInserting = false
            }
        }
    }

    private func pasteFromClipboard() {
        #if os(macOS)
        let text = NSPasteboard.general.string(forType: .string)
        #else
        let text = UIPasteboard.general.string
        #endif

        guard let text, !text.isEmpty else { return }
        inputText = text
    }
}

#Preview {
    MermaidInputSheetView { _ in }
}

private enum MermaidInputSheetPage: Hashable {
    case input
    case preview
}

private enum MermaidPreviewState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

private enum MermaidInputSheetError: LocalizedError {
    case noActiveCanvas
    case previewUnavailable

    var errorDescription: String? {
        switch self {
            case .noActiveCanvas:
                String(localizable: .mermaidInputSheetNoActiveCanvasError)
            case .previewUnavailable:
                String(localizable: .mermaidInputSheetPreviewUnavailable)
        }
    }
}

private enum MermaidPreviewRenderer {
    @MainActor
    static func renderPNGData(_ definition: String) async throws -> Data {
        let coordinator = try await AIProposalSandbox.readyCoordinator()
        try await coordinator.replaceAllElements([])

        var options = ExcalidrawCore.MermaidInsertOptions()
        options.focus = .enabled(false)
        options.position = .sceneCenter
        _ = try await coordinator.insertFromMermaid(definition, options: options)

        let file = try await currentFile(from: coordinator)
        return try await coordinator.exportElementsToPNGData(
            elements: file.elements,
            files: file.files.isEmpty ? nil : file.files,
            colorScheme: .light
        )
    }

    @MainActor
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let platformImage = NSImage(data: data) else { return nil }
        return Image(nsImage: platformImage)
        #else
        guard let platformImage = UIImage(data: data) else { return nil }
        return Image(uiImage: platformImage)
        #endif
    }

    @MainActor
    private static func currentFile(
        from coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws -> ExcalidrawFile {
        if let snapshot = try? await coordinator.getCurrentFileSnapshot() {
            return try file(fromSceneData: snapshot.documentData())
        }

        guard let result = try await coordinator.saveCurrentFile(),
              let data = result.dataString.data(using: .utf8) else {
            throw MermaidInputSheetError.previewUnavailable
        }

        return try file(fromSceneData: data)
    }

    private static func file(fromSceneData data: Data) throws -> ExcalidrawFile {
        let baseData = AIProposalSandbox.blankFileData() ?? Data()
        guard var baseObject = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            return try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        }

        let sceneObject = try JSONSerialization.jsonObject(with: data)
        if let sceneObject = sceneObject as? [String: Any] {
            for key in ["elements", "files", "appState"] {
                if let value = sceneObject[key] {
                    baseObject[key] = value
                }
            }
        } else if let elements = sceneObject as? [Any] {
            baseObject["elements"] = elements
        }

        let mergedData = try JSONSerialization.data(withJSONObject: baseObject)
        return try JSONDecoder().decode(ExcalidrawFile.self, from: mergedData)
    }
}
