//
//  ExcalidrawContainer+FileStatusObserver.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI

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
    }
    
    /// Handle file status changes for currently active file
    private func handleFileStatusChange(_ newStatus: FileStatus?) {
        guard let newStatus = newStatus else { return }
        guard case .localFile(let url) = activeFile else { return }

        // Handle conflict state - show resolution sheet immediately
        if newStatus == .conflict {
            conflictFileURL = url
            return
        }

#if os(macOS)
        // Handle file becoming outdated - trigger reload
        let shouldDownload: Bool
        if case .downloading = newStatus {
            shouldDownload = true
        } else if newStatus == .outdated {
            shouldDownload = true
        } else {
            shouldDownload = false
        }
        
        if shouldDownload && !isSyncing {
            isSyncing = true
            Task {
                if let latestData = try? await FileSyncCoordinator.shared.openFile(url) {
                    onSyncing(latestData) {}
                }
                
                isSyncing = false
            }
        }
#endif
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
    
