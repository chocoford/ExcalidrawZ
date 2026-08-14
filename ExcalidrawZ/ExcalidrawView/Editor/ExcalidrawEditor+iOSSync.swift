//
//  ExcalidrawEditor+iOSSync.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI

import ChocofordUI


#if os(iOS)
/// ViewModifier that handles iOS local-file refresh for linked iCloud files.
///
/// FileStorage-backed app files use `FileStorageICloudStatusMonitor` instead.
/// This polling fallback is kept for linked folders because those files live
/// outside FileStorage and still rely on URL-based iCloud status checks.
private struct IOSAutoSyncModifier: ViewModifier {
    @Environment(\.alertToast) var alertToast
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var toolState: ToolState
    
    var activeFile: FileState.ActiveFile?
    var activeFileLockState: FileContentLockState
    var localFileBinding: Binding<ExcalidrawFile?>
    var onUpdate: (Data) async -> Void
    
    @State private var autoSyncTask: Task<Void, Never>?
    func body(content: Content) -> some View {
        content
            .watch(value: activeFile) { file in
                if file == nil {
                    stopAutoSync()
                } else {
                    startAutoSyncIfNeeded(file: file)
                }
            }
            .watch(value: activeFileLockState) { lockState in
                if lockState == .plaintext {
                    startAutoSyncIfNeeded(file: activeFile)
                } else {
                    stopAutoSync()
                }
            }
            .watch(value: toolState.inDragMode) { inDragMode in
                if inDragMode {
                    startAutoSyncIfNeeded(file: activeFile)
                } else {
                    stopAutoSync()
                }
            }
            .watch(value: scenePhase) { scenePhase in
                if scenePhase == .background {
                    stopAutoSync()
                } else if scenePhase == .active {
                    startAutoSyncIfNeeded(file: activeFile)
                }
            }
            .onDisappear {
                stopAutoSync()
            }
    }
    
    /// Start auto-sync if in read-only mode with a linked iCloud file.
    private func startAutoSyncIfNeeded(file activeFile: FileState.ActiveFile?) {
        // Only in read-only mode (drag mode)
        guard toolState.inDragMode else {
            stopAutoSync()
            return
        }

        guard activeFileLockState == .plaintext else {
            stopAutoSync()
            return
        }
        
        // Check if should sync based on file type
        let shouldSync: Bool
        switch activeFile {
            case .localFile(let url):
                shouldSync = isICloudFile(url)
            case .file, .collaborationFile, .temporaryFile, .cloudStorageFile, .none:
                shouldSync = false
        }
        
        guard shouldSync else {
            stopAutoSync()
            return
        }
        
        // Cancel existing task
        stopAutoSync()
        
        // Start new auto-sync task
        autoSyncTask = Task {
            while !Task.isCancelled {
                // Wait for sync interval
                try? await Task.sleep(for: .seconds(5))
                
                guard !Task.isCancelled,
                      activeFileLockState == .plaintext else { break }
                
                do {
                    try await syncLatestContentIfNeeded(
                        file: activeFile
                    )
                } catch {
                    alertToast(error)
                }
            }
        }
    }

    private func syncLatestContentIfNeeded(
        file activeFile: FileState.ActiveFile?
    ) async throws {
        guard activeFileLockState == .plaintext,
              let activeFile else {
            return
        }

        let latestData: Data
        do {
            switch activeFile {
                case .localFile(let url):
                    latestData = try await FileSyncCoordinator.shared.openFile(url)

                case .file, .collaborationFile, .temporaryFile, .cloudStorageFile:
                    return
            }
        } catch {
            throw error
        }

        guard !Task.isCancelled else { return }

        let currentData = await MainActor.run {
            localFileBinding.wrappedValue?.content
        }

        guard latestData != currentData else {
            return
        }

        await markSyncInProgress(for: activeFile)

        guard !Task.isCancelled else { return }

        await onUpdate(latestData)
        await markSyncCompleted(for: activeFile)
    }

    private func markSyncInProgress(for activeFile: FileState.ActiveFile) async {
        switch activeFile {
            case .localFile(let url):
                await FileSyncCoordinator.shared.updateFileStatus(
                    for: url,
                    status: .syncing
                )
                await MainActor.run {
                    FileStatusService.shared.markSyncInProgress(
                        fileID: url.absoluteString,
                        operation: .download
                    )
                }

            case .file, .collaborationFile, .temporaryFile, .cloudStorageFile:
                return
        }
    }

    private func markSyncCompleted(for activeFile: FileState.ActiveFile) async {
        switch activeFile {
            case .localFile(let url):
                await FileSyncCoordinator.shared.updateFileStatus(
                    for: url,
                    status: .downloaded
                )
                await MainActor.run {
                    FileStatusService.shared.markSyncCompleted(fileID: url.absoluteString)
                }

            case .file, .collaborationFile, .temporaryFile, .cloudStorageFile:
                return
        }
    }
    
    /// Stop auto-sync
    private func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }
    
    /// Check if file is in iCloud Drive
    private func isICloudFile(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            return values.isUbiquitousItem == true
        } catch {
            return false
        }
    }
}

extension View {
    /// Apply iOS auto-sync behavior for iCloud files in read-only mode
    @ViewBuilder
    func applyIOSAutoSync(
        activeFile: FileState.ActiveFile?,
        activeFileLockState: FileContentLockState,
        localFileBinding: Binding<ExcalidrawFile?>,
        onUpdate: @escaping (Data) async -> Void
    ) -> some View {
        self.modifier(
            IOSAutoSyncModifier(
                activeFile: activeFile,
                activeFileLockState: activeFileLockState,
                localFileBinding: localFileBinding,
                onUpdate: onUpdate
            )
        )
    }
}
#endif
