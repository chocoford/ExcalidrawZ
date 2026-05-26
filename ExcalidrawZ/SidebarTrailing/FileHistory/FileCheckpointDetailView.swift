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
    @State private var isRecoverAlertPresented = false

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
        .alert(
            String(localizable: .deletedFileRecoverAlertTitle),
            isPresented: $isRecoverAlertPresented
        ) {
            Button(role: .cancel) {
                isRecoverAlertPresented.toggle()
            } label: {
                Text(.localizable(.deletedFileRecoverAlertButtonCancel))
            }

            Button(role: {
                if #available(iOS 26.0, macOS 26.0, *) {
                    return .confirm
                } else {
                    return .none
                }
            }()) {
                recoverActiveTrashedFile()
            } label: {
                Text(.localizable(.deletedFileRecoverAlertButtonRecover))
            }
        } message: {
            Text(.localizable(.deletedFileRecoverAlertMessage))
        }
    }

    private func restoreCheckpoint() {
        guard !fileState.currentActiveFileIsInTrash else {
            isRecoverAlertPresented = true
            return
        }

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

                // Step 2: Restore the currently active canvas through the
                // same path used by AI-chat revert, so database and local
                // file reload semantics stay aligned.
                try await fileState.restoreActiveCanvas(
                    fromCheckpointContent: content,
                    filename: checkpoint.filename
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
        }
    }

    private func recoverActiveTrashedFile() {
        guard case .file(let currentFile) = fileState.currentActiveFile else { return }
        Task {
            do {
                try await fileState.recoverFile(
                    fileID: currentFile.objectID,
                    context: viewContext
                )
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
