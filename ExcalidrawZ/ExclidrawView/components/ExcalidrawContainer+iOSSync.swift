//
//  ExcalidrawContainer+iOSSync.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI


#if os(iOS)
/// ViewModifier that handles auto-sync for iCloud files in read-only mode (iOS only)
private struct IOSAutoSyncModifier: ViewModifier {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var toolState: ToolState

    let activeFile: FileState.ActiveFile?
    let localFileBinding: Binding<ExcalidrawFile?>
    let onUpdate: (Data) async -> Void

    @State private var autoSyncTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: activeFile) { _ in
                startAutoSyncIfNeeded()
            }
            .onChange(of: toolState.inDragMode) { inDragMode in
                if inDragMode {
                    startAutoSyncIfNeeded()
                } else {
                    stopAutoSync()
                }
            }
            .task {
                startAutoSyncIfNeeded()
            }
            .onDisappear {
                stopAutoSync()
            }
    }

    /// Start auto-sync if in read-only mode with iCloud file
    private func startAutoSyncIfNeeded() {
        // Only in read-only mode (drag mode)
        guard toolState.inDragMode else {
            stopAutoSync()
            return
        }

        // Only for iCloud files
        guard case .localFile(let url) = activeFile,
              isICloudFile(url) else {
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
                    // Force download latest version
                    let latestData = try await FileSyncCoordinator.shared.openFile(url)
                    let currentData = localFileBinding.wrappedValue?.content

                    // Reload if content changed
                    if latestData != currentData {
                        Task {
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .syncing
                            )
                            try? await Task.sleep(nanoseconds: UInt64(1e+9 * 2))
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .downloaded
                            )
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
        self.modifier(IOSAutoSyncModifier(
            activeFile: activeFile,
            localFileBinding: localFileBinding,
            onUpdate: onUpdate
        ))
    }
}
#endif
