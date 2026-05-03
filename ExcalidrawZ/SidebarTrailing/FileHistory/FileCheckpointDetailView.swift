//
//  FileCheckpointDetailView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

struct FileCheckpointDetailView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var fileState: FileState

    var checkpoint: Checkpoint

    @State private var loadedContent: Data?

    init(checkpoint: Checkpoint) {
        self.checkpoint = checkpoint
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let data = loadedContent,
                   let file = try? ExcalidrawFile(data: data, id: checkpoint.fileID),
                   !file.elements.isEmpty {
                     ExcalidrawRenderer(file: file)
                } else {
                    if colorScheme == .light {
                        Color.white
                    } else {
                        Color.black
                    }
                }
            }
            .frame(width: 400, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkpoint.filename ?? "")
                        .font(.title2.bold())
                    Text(checkpoint.updatedAt?.formatted() ?? "")
                        .font(.footnote)
                }

                Spacer()

                if #available(macOS 26.0, iOS 26.0, *) {
                    HStack {
                        Button {
                            viewContext.delete(checkpoint)
                            dismiss()
                        } label: {
                            Image(systemSymbol: .trash)
                                .foregroundStyle(.red)
                        }
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass)
                        
                        Button { @MainActor in
                            restoreCheckpoint()
                        } label: {
                            Text(.localizable(.checkpointButtonRestore))
                        }
                        .buttonBorderShape(.capsule)
                        .buttonStyle(.glassProminent)
                    }
                    .controlSize(.extraLarge)
                } else {
                    HStack {
                        Button {
                            viewContext.delete(checkpoint)
                            dismiss()
                        } label: {
                            Image(systemSymbol: .trash)
                                .foregroundStyle(.red)
                        }
                        
                        Button { @MainActor in
                            restoreCheckpoint()
                        } label: {
                            Text(.localizable(.checkpointButtonRestore))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                }
                
                
            }
            .padding(20)
        }
        .task {
            // Load checkpoint content asynchronously
            if let fileCheckpoint = checkpoint as? FileCheckpoint {
                loadedContent = try? await fileCheckpoint.loadContent()
            } else {
                // Fallback for non-FileCheckpoint types (like CollaborationFileCheckpoint)
                loadedContent = checkpoint.content
            }
        }
    }

    private func restoreCheckpoint() {
        Task {
            do {
                // Step 1: Load checkpoint content (background)
                let content: Data
                if let fileCheckpoint = checkpoint as? FileCheckpoint {
                    content = try await fileCheckpoint.loadContent()
                } else {
                    guard let checkpointContent = checkpoint.content else { return }
                    content = checkpointContent
                }

                // Step 2: Handle different file types
                if checkpoint.fileID != nil {
                    // Database file: Update on main thread
                    await MainActor.run {
                        if case .file(let file) = fileState.currentActiveFile {
                            file.content = content
                            file.name = checkpoint.filename
                            Task { await fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true) }
                        }
                        fileState.didUpdateFile = false
                        dismiss()
                    }
                } else if case .localFolder(let folder) = fileState.currentActiveGroup,
                          case .localFile(let fileURL) = fileState.currentActiveFile {
                    // Parse file for UI update (before security-scoped access)
                    var parsedFile = try ExcalidrawFile(data: content)
                    parsedFile.id = ExcalidrawFile.localFileURLIDMapping[fileURL] ?? UUID().uuidString

                    // Local file: Write to disk with security-scoped access
                    try await folder.withSecurityScopedURL { _ in
                        // Write to disk with FileCoordinator (background operation)
                        try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: content)
                    }

                    // Update UI on main thread (after file is written)
                    await MainActor.run {
                        Task { await fileState.excalidrawWebCoordinator?.loadFile(from: parsedFile, force: true) }
                        fileState.didUpdateFile = false
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    FileCheckpointDetailView(checkpoint: FileCheckpoint.preview)
}
#endif
