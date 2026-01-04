//
//  ExcalidrawContainer+iOSSync.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI


#if os(iOS)
/// ViewModifier that handles auto-sync for iCloud-synced files in read-only mode (iOS only)
/// Supports: LocalFile (iCloud Drive), CoreData File, CollaborationFile
/// Uses polling (5s interval) to detect changes from other devices
private struct IOSAutoSyncModifier: ViewModifier {
    @Environment(\.alertToast) var alertToast
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var toolState: ToolState
    
    var activeFile: FileState.ActiveFile?
    var localFileBinding: Binding<ExcalidrawFile?>
    var onUpdate: (Data) async -> Void
    
    @State private var autoSyncTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: activeFile) { file in
                if file == nil {
                    stopAutoSync()
                } else {
                    startAutoSyncIfNeeded(file: file)
                }
            }
            .onChange(of: toolState.inDragMode) { inDragMode in
                if inDragMode {
                    startAutoSyncIfNeeded(file: activeFile)
                } else {
                    stopAutoSync()
                }
            }
            .onChange(of: scenePhase) { scenePhase in
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
    
    /// Start auto-sync if in read-only mode with iCloud file
    private func startAutoSyncIfNeeded(file activeFile: FileState.ActiveFile?) {
        // Only in read-only mode (drag mode)
        guard toolState.inDragMode else {
            stopAutoSync()
            return
        }
        
        // Check if should sync based on file type
        let shouldSync: Bool
        switch activeFile {
            case .localFile(let url):
                shouldSync = isICloudFile(url)
            case .file, .collaborationFile:
                // CoreData files are always in iCloud Drive container
                shouldSync = true
            case .temporaryFile, .none:
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
                
                guard !Task.isCancelled else { break }
                
                do {
                    // Load latest content based on file type
                    let latestData: Data
                    
                    switch activeFile {
                        case .localFile(let url):
                            // LocalFile: use FileSyncCoordinator
                            latestData = try await FileSyncCoordinator.shared.openFile(url)
                            
                        case .file(let dbFile):
                            guard let fileID = dbFile.id else { continue }
                            // CoreData File: use FileStorageManager
                            let relativePath = FileStorageContentType.file.generateRelativePath(
                                fileID: fileID.uuidString
                            )
                            latestData = try await FileStorageManager.shared.loadContent(
                                relativePath: relativePath,
                                fileID: fileID.uuidString
                            )
                            
                        case .collaborationFile(let collabFile):
                            guard let fileID = collabFile.id else { continue }
                            // CollaborationFile: use FileStorageManager
                            let relativePath = FileStorageContentType.collaborationFile.generateRelativePath(
                                fileID: fileID.uuidString
                            )
                            latestData = try await FileStorageManager.shared.loadContent(
                                relativePath: relativePath,
                                fileID: fileID.uuidString
                            )
                            // collaboration file no need to load file.
                            return
                        default:
                            continue
                    }
                    
                    let currentData = localFileBinding.wrappedValue?.content
                    
                    // Reload if content changed
                    if latestData != currentData {
                        // Update file status to show sync indicator
                        if case .localFile(let url) = activeFile {
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .syncing
                            )
                            try? await Task.sleep(nanoseconds: UInt64(1e+9 * 2))
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .downloaded
                            )
                        } else if let fileID = activeFile?.id {
                            await MainActor.run {
                                FileStatusService.shared.updateICloudStatus(
                                    fileID: fileID,
                                    status: .syncing
                                )
                            }
                            try? await Task.sleep(nanoseconds: UInt64(1e+9 * 2))
                            await MainActor.run {
                                FileStatusService.shared.updateICloudStatus(
                                    fileID: fileID,
                                    status: .downloaded
                                )
                            }
                        }
                        
                        await onUpdate(latestData)
                    }
                } catch {
                    alertToast(error)
                }
            }
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
        localFileBinding: Binding<ExcalidrawFile?>,
        onUpdate: @escaping (Data) async -> Void
    ) -> some View {
        self.modifier(
            IOSAutoSyncModifier(
                activeFile: activeFile,
                localFileBinding: localFileBinding,
                onUpdate: onUpdate
            )
        )
    }
}
#endif
