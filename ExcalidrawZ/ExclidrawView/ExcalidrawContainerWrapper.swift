//
//  ExcalidrawContainerWrapper.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI

struct ExcalidrawContainerWrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState

    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool

    @State private var isSettingsPresented = false
    @State private var excalidrawFile: ExcalidrawFile?
    @State private var isLoadingFile = false
    @State private var shouldShowLoadingMask = false
    @State private var loadingTask: Task<Void, Never>?

    init(
        activeFile: Binding<FileState.ActiveFile?>,
        interactionEnabled: Bool = true
    ) {
        self._activeFile = activeFile
        self.interactionEnabled = interactionEnabled
    }

    var localFileBinding: Binding<ExcalidrawFile?> {
        Binding<ExcalidrawFile?> {
            return excalidrawFile
        } set: { val in
            guard let val else { return }

            // Block updates while loading new file
            guard !isLoadingFile else {
                print("[localFileBinding.set] Blocked update during file loading")
                return
            }

            switch activeFile {
                case .file(let file):
                    if file.id == val.id {
                        // Check if there are actual updates
                        if let currentFile = excalidrawFile, val.elements == currentFile.elements {
                            print("[updateCurrentFile] no updates, ignored.")
                            return
                        }
                        fileState.updateFile(file, with: val)
                    }
                case .localFile(let url):
                    guard case .localFolder(let folder) = fileState.currentActiveGroup else { return }
                    Task {
                        try folder.withSecurityScopedURL { _ in
                            do {
                                let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                if val.elements == oldElements {
                                    print("[updateCurrentFile] no updates, ignored.")
                                    return
                                }
                                try await fileState.updateLocalFile(
                                    to: url,
                                    with: val,
                                    context: viewContext
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                case .temporaryFile(let url):
                    Task {
                        do {
                            let oldElements = try ExcalidrawFile(contentsOf: url).elements
                            if val.elements == oldElements {
                                print("[updateCurrentFile] no updates, ignored.")
                                return
                            }
                            try await fileState.updateLocalFile(
                                to: url,
                                with: val,
                                context: viewContext
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                default:
                    break
            }
        }
    }
    
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = activeFile {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        ZStack {
            ExcalidrawContainerView(
                file: localFileBinding,
                interactionEnabled: interactionEnabled
            )
            .opacity(isInCollaborationSpace ? 0 : 1)
            .allowsHitTesting(!isInCollaborationSpace && !isLoadingFile)

            ExcalidrawCollabContainerView()
                .opacity(isInCollaborationSpace ? 1 : 0)
                .allowsHitTesting(isInCollaborationSpace && !isLoadingFile)

            // Loading mask
            if shouldShowLoadingMask {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading...")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(interactionEnabled)
        .animation(.easeInOut(duration: 0.2), value: shouldShowLoadingMask)
        .onChange(of: activeFile) { (newFile: FileState.ActiveFile?) in
            loadingTask?.cancel()
            loadingTask = Task {
                await loadExcalidrawFile(from: newFile)
            }
        }
        .task {
            await loadExcalidrawFile(from: activeFile)
        }
    }

    private func loadExcalidrawFile(from activeFile: FileState.ActiveFile?) async {
        // Set loading state
        await MainActor.run {
            self.isLoadingFile = true
        }

        // Show loading mask after 1 second delay
        let maskTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            if !Task.isCancelled {
                await MainActor.run {
                    self.shouldShowLoadingMask = true
                }
            }
        }

        defer {
            maskTask.cancel()
            Task { @MainActor in
                self.isLoadingFile = false
                self.shouldShowLoadingMask = false
            }
        }

        do {
            switch activeFile {
                case .file(let file):
                    let content = try await file.loadContent()
                    await MainActor.run {
                        self.excalidrawFile = try? ExcalidrawFile(data: content, id: file.id)
                    }
                case .localFile(let url):
                    let file = try ExcalidrawFile(contentsOf: url)
                    await MainActor.run {
                        self.excalidrawFile = file
                    }
                case .temporaryFile(let url):
                    let file = try ExcalidrawFile(contentsOf: url)
                    await MainActor.run {
                        self.excalidrawFile = file
                    }
                default:
                    await MainActor.run {
                        self.excalidrawFile = nil
                    }
            }
        } catch {
            alertToast(error)
            await MainActor.run {
                self.excalidrawFile = nil
            }
        }
    }
}
