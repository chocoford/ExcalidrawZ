//
//  AIProposalToolResultCard.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/01.
//

import ChocofordEssentials
import ChocofordUI
import Foundation
import LLMCore
import SFSafeSymbols
import SwiftUI
import UniformTypeIdentifiers

struct AIProposalToolResultCard: View {
    @EnvironmentObject private var fileState: FileState
    @Environment(\.alertToast) private var alertToast

    let artifact: AIProposalArtifact
    let previewFile: ChatMessageContent.File?
    let onDismiss: (() -> Void)?

    @State private var isApplying = false
    @State private var applyCount = 0

    init(
        artifact: AIProposalArtifact,
        previewFile: ChatMessageContent.File?,
        onDismiss: (() -> Void)? = nil
    ) {
        self.artifact = artifact
        self.previewFile = previewFile
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            AIProposalPreviewImageView(
                artifact: artifact,
                previewFile: previewFile
            )
            .frame(maxWidth: .infinity)
#if os(macOS)
            .onDrag {
                makeProposalDragItemProvider()
            }
#endif
            
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(spacing: 8) {
                    Text(.localizable(.aiProposalElementCount(artifact.elementCount)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 8)

                    if let onDismiss {
                        Button(String(localizable: .generalButtonDismiss)) {
                            onDismiss()
                        }
                        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
                    }
                    
                    Button {
                        applyProposal()
                    } label: {
                        if isApplying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                applyCount > 0
                                ? String(localizable: .aiProposalAddAgainButton)
                                : String(localizable: .aiProposalApplyButton),
                                systemSymbol: .plus
                            )
                        }
                    }
                    .modernButtonStyle(style: .glassProminent, size: .regular, shape: .capsule)
                    .disabled(isApplying)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.purple.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.purple.opacity(0.16), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemSymbol: .sparkles)
                .font(.caption.weight(.semibold))
            Text(.localizable(.aiProposalTitle))
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.purple)
    }

#if os(macOS)
    private func makeProposalDragItemProvider() -> NSItemProvider {
        let library = ExcalidrawLibrary(
            type: "excalidrawlib",
            version: 2,
            source: "https://excalidraw.com",
            libraryItems: [
                ExcalidrawLibrary.Item(
                    id: UUID().uuidString,
                    status: .published,
                    createdAt: Date(),
                    name: String(localizable: .aiProposalDragName),
                    elements: artifact.visibleElements
                )
            ]
        )
        do {
            let data = Data(try library.jsonStringified().utf8)
            return NSItemProvider(
                item: data as NSData,
                typeIdentifier: UTType.excalidrawlibJSON.identifier
            )
        } catch {
            alertToast(error)
            return NSItemProvider()
        }
    }
#endif

    @MainActor
    private func applyProposal() {
        guard !isApplying else { return }
        isApplying = true

        Task { @MainActor in
            defer { isApplying = false }

            do {
                let canvasTarget = activeUserCanvasTarget
                guard let coordinator = activeUserCanvasCoordinator else {
                    throw AIProposalApplyError.noActiveCanvas
                }

                let files = Array(artifact.file.files.values)
                if !files.isEmpty {
                    try await coordinator.insertMediaFiles(files)
                }

                let elements = artifact.visibleElements
                guard !elements.isEmpty else {
                    throw AIProposalApplyError.emptyProposal
                }

                let regeneratedElements = try AIProposalElementIDRegenerator.regenerate(elements)
                try await coordinator.addElements(regeneratedElements)
                try? await ExcalidrawCoordinatorRegistry.shared
                    .cameraDirector(for: canvasTarget)
                    .submitMutationBatch(
                        elements: regeneratedElements,
                        changedElementIDs: regeneratedElements.map(\.id),
                        mode: .replace
                    )

                withAnimation(.easeInOut(duration: 0.18)) {
                    applyCount += 1
                }
                onDismiss?()
            } catch {
                alertToast.presentAIChatError(error)
            }
        }
    }

    @MainActor
    private var activeUserCanvasCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator
            default:
                fileState.excalidrawWebCoordinator
        }
    }

    @MainActor
    private var activeUserCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                .collaboration
            default:
                .normal
        }
    }
}

private struct AIProposalPreviewImageView: View {
    let artifact: AIProposalArtifact
    let previewFile: ChatMessageContent.File?

    @State private var image: Image?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 200)

            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 200)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: artifact) {
            await loadPreview()
        }
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        defer { isLoading = false }

        if let data = await Self.previewData(from: previewFile),
           let platformImage = PlatformImage(data: data) {
            image = Image(platformImage: platformImage)
            return
        }

        guard let data = await AIProposalPreviewRenderer.renderData(for: artifact),
              let platformImage = PlatformImage(data: data) else {
            image = nil
            return
        }

        image = Image(platformImage: platformImage)
    }

    private static func previewData(from file: ChatMessageContent.File?) async -> Data? {
        guard let file else { return nil }
        return await Task.detached(priority: .userInitiated) {
            switch file {
                case .base64EncodedImage(let dataURI):
                    guard let base64 = dataURI.components(separatedBy: ",").last else { return nil }
                    return Data(base64Encoded: base64)
                case .image(let url):
                    guard url.isFileURL else { return nil }
                    return try? Data(contentsOf: url)
            }
        }.value
    }
}

private enum AIProposalPreviewRenderer {
    @MainActor
    static func renderData(for artifact: AIProposalArtifact) async -> Data? {
        guard let coordinator = try? await AIProposalSandbox.readyCoordinator() else {
            return nil
        }

        return try? await coordinator.exportElementsToPNGData(
            elements: artifact.visibleElements,
            files: artifact.file.files.isEmpty ? nil : artifact.file.files,
            colorScheme: .light
        )
    }
}

private enum AIProposalElementIDRegenerator {
    static func regenerate(_ elements: [ExcalidrawElement]) throws -> [ExcalidrawElement] {
        let data = try JSONEncoder().encode(elements)
        guard var objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !objects.isEmpty else {
            return elements
        }

        let idMapping = makeElementIDMapping(objects)
        let groupIDMapping = makeGroupIDMapping(objects)
        for index in objects.indices {
            objects[index] = remapIDs(
                in: objects[index],
                idMapping: idMapping,
                groupIDMapping: groupIDMapping
            )
        }

        let remappedData = try JSONSerialization.data(withJSONObject: objects)
        return try JSONDecoder().decode([ExcalidrawElement].self, from: remappedData)
    }

    private static func makeElementIDMapping(_ elements: [[String: Any]]) -> [String: String] {
        var mapping: [String: String] = [:]
        for element in elements {
            if let id = element["id"] as? String {
                mapping[id] = mapping[id] ?? ExcalidrawNanoID.make()
            }
        }
        return mapping
    }

    private static func makeGroupIDMapping(_ elements: [[String: Any]]) -> [String: String] {
        var mapping: [String: String] = [:]
        for element in elements {
            guard let groupIDs = element["groupIds"] as? [String] else { continue }
            for groupID in groupIDs {
                mapping[groupID] = mapping[groupID] ?? ExcalidrawNanoID.make()
            }
        }
        return mapping
    }

    private static func remapIDs(
        in element: [String: Any],
        idMapping: [String: String],
        groupIDMapping: [String: String]
    ) -> [String: Any] {
        var output = element

        if let id = output["id"] as? String,
           let newID = idMapping[id] {
            output["id"] = newID
        }

        for key in ["containerId", "frameId"] {
            if let id = output[key] as? String,
               let newID = idMapping[id] {
                output[key] = newID
            }
        }

        if var boundElements = output["boundElements"] as? [[String: Any]] {
            for index in boundElements.indices {
                if let id = boundElements[index]["id"] as? String,
                   let newID = idMapping[id] {
                    boundElements[index]["id"] = newID
                }
            }
            output["boundElements"] = boundElements
        }

        for key in ["startBinding", "endBinding"] {
            if var binding = output[key] as? [String: Any],
               let id = binding["elementId"] as? String,
               let newID = idMapping[id] {
                binding["elementId"] = newID
                output[key] = binding
            }
        }

        if let groupIDs = output["groupIds"] as? [String] {
            output["groupIds"] = groupIDs.map { groupIDMapping[$0] ?? $0 }
        }

        return output
    }
}

private enum AIProposalApplyError: LocalizedError {
    case emptyProposal
    case noActiveCanvas

    var errorDescription: String? {
        switch self {
            case .emptyProposal:
                String(localizable: .aiProposalErrorEmpty)
            case .noActiveCanvas:
                String(localizable: .aiProposalErrorNoActiveCanvas)
        }
    }
}
