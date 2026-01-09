//
//  LocalFolderMonitorModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/22/25.
//

import SwiftUI
import CoreData
import Logging

/// ViewModifier that monitors all LocalFolders for file system and iCloud changes
/// Should be applied once at the root view level to avoid duplicate monitoring
struct LocalFolderMonitorModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @StateObject private var localFolderState = LocalFolderState()
    
    private let logger = Logger(label: "LocalFolderMonitor")
    
    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.rank, order: .forward),
            SortDescriptor(\.importedAt, order: .forward),
        ],
        predicate: NSPredicate(format: "parent == nil")
    )
    var folders: FetchedResults<LocalFolder>

    @State private var eventStreamTask: Task<Void, Never>?
    @State private var registeredFolders: Set<NSManagedObjectID> = []
    @State private var folderURLs: [NSManagedObjectID: URL] = [:]

    func body(content: Content) -> some View {
        content
            .environmentObject(localFolderState)
            .watch(value: folders) { newValue in
                handleFoldersObservation(folders: newValue)
            }
            .onAppear {
                startListeningToFileChanges()
            }
            .onDisappear {
                eventStreamTask?.cancel()
                eventStreamTask = nil
            }
    }
    
    private func handleFoldersObservation(folders newValue: FetchedResults<LocalFolder>) {
        // Get current folder IDs
        let currentFolderIDs = Set(newValue.map { $0.objectID })

        // Find folders to add (in newValue but not in registeredFolders)
        let folderIDsToAdd = currentFolderIDs.subtracting(registeredFolders)

        // Find folders to remove (in registeredFolders but not in newValue)
        let folderIDsToRemove = registeredFolders.subtracting(currentFolderIDs)

        // Register new folders
        for folderID in folderIDsToAdd {
            guard let folder = try? viewContext.existingObject(with: folderID) as? LocalFolder else {
                continue
            }

            Task {
                do {
                    try await folder.withSecurityScopedURL { scopedURL in
                        try await FileSyncCoordinator.shared.addFolder(at: scopedURL, options: .default)
                        await MainActor.run {
                            // Store URL for future removal
                            folderURLs[folderID] = scopedURL
                        }
                        logger.info("Registered folder with FileSyncCoordinator: \(scopedURL.filePath)")
                    }
                } catch {
                    logger.error("Failed to access security-scoped URL: \(error)")
                    await MainActor.run {
                        alertToast(error)
                    }
                }
            }
        }

        // Unregister removed folders
        for folderID in folderIDsToRemove {
            guard let url = folderURLs[folderID] else {
                logger.warning("Cannot unregister folder - URL not found: \(folderID)")
                continue
            }

            Task {
                await FileSyncCoordinator.shared.removeFolder(at: url)
                await MainActor.run {
                    _ = folderURLs.removeValue(forKey: folderID)
                }
                logger.info("Unregistered folder from FileSyncCoordinator: \(url.lastPathComponent)")
            }
        }

        // Update registered folders set
        registeredFolders = currentFolderIDs
    }
    
    /// Listen to FileSyncCoordinator events and forward to LocalFolderState
    private func startListeningToFileChanges() {
        eventStreamTask = Task {
            for await event in await FileSyncCoordinator.shared.fileChangesStream {
                handleFileChangeEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleFileChangeEvent(_ event: FSChangeEvent) {
        let path = switch event {
            case .created(let url): url.filePath
            case .modified(let url): url.filePath
            case .deleted(let url): url.filePath
            case .renamed(_, let newURL): newURL.filePath
            case .statusChanged(let url, _): url.filePath
        }
        
        // Only handle .excalidraw files
        guard path.hasSuffix(".excalidraw") else { return }
        
        switch event {
            case .created(let url):
                logger.debug("File created: \(url.lastPathComponent)")
                localFolderState.itemCreatedPublisher.send(path)
                
                // Refresh parent folder if it's a directory
                refreshParentFolderIfNeeded(for: url)
                
            case .modified(let url):
                logger.debug("File modified: \(url.lastPathComponent)")
                localFolderState.itemUpdatedPublisher.send(path)
                
            case .deleted(let url):
                logger.debug("File deleted: \(url.lastPathComponent)")
                localFolderState.itemRemovedPublisher.send(path)
                
            case .renamed(let oldURL, let newURL):
                logger.debug("File renamed: \(oldURL.lastPathComponent) -> \(newURL.lastPathComponent)")
                localFolderState.itemRenamedPublisher.send(newURL.filePath)
                
                // Refresh parent folder
                refreshParentFolderIfNeeded(for: newURL)
                
            case .statusChanged(let url, let status):
                logger.debug("File status changed: \(url.lastPathComponent) - \(status)")
                
                // Forward to NotificationCenter for backward compatibility
                NotificationCenter.default.post(
                    name: .iCloudFileStatusDidChange,
                    object: url,
                    userInfo: ["status": status]
                )
                
                // Handle download events
                if case .downloading = status {
                    NotificationCenter.default.post(
                        name: .iCloudFileDidStartDownloading,
                        object: url
                    )
                } else if case .downloaded = status {
                    NotificationCenter.default.post(
                        name: .iCloudFileDidFinishDownloading,
                        object: url
                    )
                    localFolderState.refreshFilesPublisher.send()
                }
        }
    }
    
    @MainActor
    private func refreshParentFolderIfNeeded(for url: URL) {
        let parentURL = url.deletingLastPathComponent()
        
        // Find the LocalFolder that contains this file
        for folder in folders {
            guard let folderURL = folder.url else { continue }
            
            if parentURL.filePath.hasPrefix(folderURL.filePath) {
                do {
                    try folder.refreshChildren(context: viewContext)
                } catch {
                    logger.error("Failed to refresh folder children: \(error)")
                    alertToast(error)
                }
                break
            }
        }
    }
}
