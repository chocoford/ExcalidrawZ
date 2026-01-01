//
//  ExcalidrawContainer+FileStatusObserver.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI
import CoreData

private struct FileStatusObserverModifier: ViewModifier {
    @EnvironmentObject private var fileState: FileState
    
    var activeFile: FileState.ActiveFile?
    @Binding private var conflictFileURL: URL?
    var onSyncing: (Data, _ onDone: @escaping () -> Void) -> Void
    var onResolveConflict: (URL) -> Void
    
    init(
        activeFile: FileState.ActiveFile?,
        conflictFileURL: Binding<URL?>,
        onSyncing: @escaping (Data, _ onDone: @escaping () -> Void) -> Void,
        onResolveConflict: @escaping (URL) -> Void
    ) {
        self.activeFile = activeFile
        self._conflictFileURL = conflictFileURL
        self.onSyncing = onSyncing
        self.onResolveConflict = onResolveConflict
    }
    
    @State private var isSyncing = false
    @State private var cloudCheckTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .observeFileStatus(for: activeFile) { status in
                handleFileStatusChange(status)
            }
            .overlay(alignment: .top) {
                if isSyncing {
                    HStack {
                        if #available(macOS 26.0, iOS 26.0, *) {
                            Image(systemSymbol: .icloudAndArrowDown)
                                .drawOnAppear(options: .speed(2))
                        } else {
                            Image(systemSymbol: .icloudAndArrowDown)
                        }
                        Text(.localizable(.iCloudStatusSyncing))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            Capsule()
                                .fill(.background)
                                .glassEffect(.clear, in: Capsule())
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .padding()
                    .transition(.move(edge: .top))
                }
            }
            .animation(.smooth, value: isSyncing)
            .sheet(isPresented: Binding {
                conflictFileURL != nil
            } set: {
                if !$0 {
                    conflictFileURL = nil
                }
            }) {
                if let conflictURL = conflictFileURL {
                    ConflictResolutionSheetView(
                        fileURL: conflictURL
                    ) {
                        onResolveConflict(conflictURL)
                    } onCancelled: {
                        fileState.setActiveFile(nil)
                    }
                }
            }
            .task {
                // Start periodic iCloud check for CoreData files
                startCloudCheckIfNeeded()
            }
            .onChange(of: activeFile) { _ in
                // Restart check when file changes
                cloudCheckTask?.cancel()
                startCloudCheckIfNeeded()
            }
    }
    
    /// Handle file status changes for currently active file
    private func handleFileStatusChange(_ status: FileStatus) {
        guard let file = activeFile else { return }
        
        // Handle iCloudStatus (unified for all file types)
        handleICloudStatus(status.iCloudStatus, for: file)
    }
    
    /// Unified iCloud status handling for all file types
    private func handleICloudStatus(_ iCloudStatus: ICloudFileStatus, for file: FileState.ActiveFile) {
        // Handle conflict state - show resolution sheet immediately
        if iCloudStatus == .conflict {
            if case .localFile(let url) = file {
                conflictFileURL = url
            }
            // CoreData File conflicts are handled differently (not implemented yet)
            return
        }
        
#if os(macOS)
        // Handle file becoming outdated - trigger reload
        let shouldDownload: Bool
        if case .downloading = iCloudStatus {
            shouldDownload = true
        } else if iCloudStatus == .outdated {
            shouldDownload = true
        } else {
            shouldDownload = false
        }
        
        if shouldDownload && !isSyncing {
            isSyncing = true
            Task {
                switch file {
                    case .localFile(let url):
                        // LocalFile: use FileSyncCoordinator
                        if let latestData = try? await FileSyncCoordinator.shared.openFile(url) {
                            onSyncing(latestData) {}
                        }
                        
                    case .file(let dbFile):
                        guard let fileID = dbFile.id else { return }
                        // CoreData File: use FileStorageManager
                        let relativePath = FileStorageContentType.file.generateRelativePath(
                            fileID: fileID.uuidString
                        )
                        if let latestData = try? await FileStorageManager.shared.loadContent(
                            relativePath: relativePath,
                            fileID: fileID.uuidString
                        ) {
                            onSyncing(latestData) {}
                        }
                        
                    case .collaborationFile(let collabFile):
                        guard let fileID = collabFile.id else { return }

                        // CollaborationFile: use FileStorageManager
                        let relativePath = FileStorageContentType.collaborationFile.generateRelativePath(
                            fileID: fileID.uuidString
                        )
                        if let latestData = try? await FileStorageManager.shared.loadContent(
                            relativePath: relativePath,
                            fileID: fileID.uuidString
                        ) {
                            onSyncing(latestData) {}
                        }
                        
                    default:
                        break
                }
                
                isSyncing = false
            }
        }
#endif
    }
    
    /// Start periodic iCloud check for CoreData files
    private func startCloudCheckIfNeeded() {
        // Only check for CoreData files
        guard case .file(let dbFile) = activeFile, let fileID = dbFile.id?.uuidString else {
            // For CollaborationFile, we could also add checks here
            return
        }
        
        let relativePath = FileStorageContentType.file.generateRelativePath(fileID: fileID)
        
        cloudCheckTask = Task {
            // Wait a bit before first check (give time for initial load)
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            while !Task.isCancelled {
                guard !Task.isCancelled else { break }
                
                // Check if iCloud has newer version
                if let hasUpdate = try? await FileStorageManager.shared.checkForICloudUpdate(
                    relativePath: relativePath,
                    fileID: fileID
                ) {
                    if hasUpdate {
                        // Update FileStatusService to trigger UI refresh
                        await MainActor.run {
                            FileStatusService.shared.updateICloudStatus(
                                fileID: fileID,
                                status: .outdated
                            )
                        }
                    }
                }
                
                // Wait before next check (30 seconds)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func observeExcalidrawFileStatus(
        for file: FileState.ActiveFile?,
        conflictFileURL: Binding<URL?>,
        onSyncing: @escaping (Data, _ onDone: @escaping () -> Void) -> Void,
        onResolveConflict: @escaping (URL) -> Void
    ) -> some View {
        modifier(
            FileStatusObserverModifier(
                activeFile: file,
                conflictFileURL: conflictFileURL,
                onSyncing: onSyncing,
                onResolveConflict: onResolveConflict
            )
        )
    }
}

