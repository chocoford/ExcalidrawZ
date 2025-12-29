//
//  ExcalidrawContainerWrapper.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI
import Combine
import CoreData

import Logging

struct ExcalidrawContainerWrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState
    @EnvironmentObject var toolState: ToolState

    let logger = Logger(label: "ExcalidrawContainerWrapper")
    
    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool

    @State private var isSettingsPresented = false
    @State private var excalidrawFile: ExcalidrawFile?
    @State private var isLoadingFile = false
    @State private var shouldShowLoadingMask = false
    @State private var loadingTask: Task<Void, Never>?

    @State private var conflictFileURL: URL?
    @State private var isSyncing = false

    // MARK: - Smart Sync State

    /// Latest cloud data from observeExcalidrawFileStatus (not immediately applied)
    @State private var latestCloudData: Data?
    /// Last received file content from WebView (for change detection)
    @State private var lastReceivedFileContent: Data?
    /// Last time the user edited the file (applyExcalidrawFile was called with actual changes)
    @State private var lastEditTime: Date?
    /// Task waiting to apply deferred cloud updates (cancellable)
    @State private var cloudSyncTask: Task<Void, Never>?
    /// Idle timeout in seconds before applying cloud updates
    private let idleTimeout: TimeInterval = 2.0

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
                logger.info("Blocked update during file loading")
                return
            }
            
            if toolState.inDragMode { return }
            
            switch activeFile {
                case .file(let file):
                    if file.id == val.id {
                        // Check if there are actual updates
                        if let currentFile = excalidrawFile, val.elements == currentFile.elements {
                            logger.info("no updates, ignored.")
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
                                    logger.info("no updates, ignored.")
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
                                logger.info("no updates, ignored.")
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
            ZStack {
                ExcalidrawContainerView(
                    file: Binding {
                        localFileBinding.wrappedValue
                    } set: { val in
                        applyExcalidrawFile(val)
                    },
                    interactionEnabled: interactionEnabled
                )
                .opacity(isInCollaborationSpace ? 0 : 1)
                .allowsHitTesting(!isInCollaborationSpace && !isLoadingFile)

                ExcalidrawCollabContainerView()
                    .opacity(isInCollaborationSpace ? 1 : 0)
                    .allowsHitTesting(isInCollaborationSpace && !isLoadingFile)
            }
            .opacity(isLoadingFile ? 0 : 1)
            .animation(.smooth, value: isLoadingFile)
            
            // Loading mask
            if isLoadingFile {
                ZStack {
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
        .observeExcalidrawFileStatus(
            for: activeFile,
            conflictFileURL: $conflictFileURL,
        ) { latestData, onDone in
            handleLatestData(latestData)
        } onResolveConflict: { url in
            // Conflict resolution should apply immediately
            loadingTask?.cancel()
            loadingTask = Task {
                if let latestData = try? await FileSyncCoordinator.shared.openFile(url) {
                    await pullUpdatingFromCloud(latestData: latestData)
                }
            }
        }
#if os(iOS)
        .applyIOSAutoSync(
            activeFile: activeFile,
            localFileBinding: localFileBinding
        ) { latestData in
            await pullUpdatingFromCloud(latestData: latestData)
        }
#endif
        .applyCloudKitSync(
            activeFile: activeFile,
            isLoadingFile: isLoadingFile,
            onReloadNeeded: {
                loadingTask?.cancel()
                loadingTask = Task {
                    await loadExcalidrawFile(from: activeFile)
                }
            }
        )
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
        
        defer {
            Task {
                await MainActor.run {
                    if self.conflictFileURL == nil {
                        self.isLoadingFile = false
                    }
                }
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
                    // Load file after download completes (or immediately if already available)
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
    
    private func handleLatestData(_ latestData: Data) {
        // Check if user has been idle long enough
        let isIdle = if let lastEdit = lastEditTime {
            Date().timeIntervalSince(lastEdit) > idleTimeout
        } else {
            true  // No edit yet, consider idle
        }

        if isIdle {
            // User is idle, apply cloud update immediately
            logger.info("User idle, applying cloud update immediately")
            cloudSyncTask?.cancel()  // Cancel any pending task
            isSyncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSyncing = false
            }
            Task {
                await pullUpdatingFromCloud(latestData: latestData)
            }
        } else {
            // User is actively editing, defer cloud update and wait for idle
            logger.info("User is editing, deferring cloud update and starting wait task")
            self.latestCloudData = latestData

            // Cancel previous task if any
            cloudSyncTask?.cancel()

            // Start new task to wait for idle
            cloudSyncTask = Task {
                // Wait for idle timeout
                try? await Task.sleep(nanoseconds: UInt64(idleTimeout * 1_000_000_000))

                // Check if still idle and still have cloud data
                if let lastEdit = await MainActor.run(body: { self.lastEditTime }),
                   Date().timeIntervalSince(lastEdit) >= idleTimeout,
                   let stillCloudData = await MainActor.run(body: { self.latestCloudData }) {
                    // Apply deferred cloud update
                    await MainActor.run {
                        self.logger.info("Wait task: User became idle, applying deferred cloud update")
                        self.latestCloudData = nil
                        self.cloudSyncTask = nil
                        self.isSyncing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.isSyncing = false
                        }
                    }
                    await pullUpdatingFromCloud(latestData: stillCloudData)
                } else {
                    await MainActor.run {
                        self.cloudSyncTask = nil
                    }
                }
            }
        }
    }

    private func pullUpdatingFromCloud(latestData: Data) async {
        self.logger.info("pullUpdatingFromCloud")
        do {
            let file = try ExcalidrawFile(data: latestData, id: excalidrawFile?.id)
            await MainActor.run {
                self.excalidrawFile = file
                NotificationCenter.default.post(name: .forceReloadExcalidrawFile, object: nil)
            }
        } catch {
            alertToast(error)
            await MainActor.run {
                self.excalidrawFile = nil
            }
        }
    }

    /// Compare only elements and appState fields from two JSON data
    private func compareExcalidrawContent(_ data1: Data, _ data2: Data) -> Bool {
        do {
            guard let dict1 = try JSONSerialization.jsonObject(with: data1) as? [String: Any],
                  let dict2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
                return false
            }
            
            if let elements1 = dict1["elements"] as? [Any],
               let elements2 = dict2["elements"] as? [Any] {
                logger.info("elements1: \(elements1.count) -- elements2: \(elements2.count)")
            }

            // Compare elements
            let elements1JSON = try JSONSerialization.data(withJSONObject: dict1["elements"] ?? [])
            let elements2JSON = try JSONSerialization.data(withJSONObject: dict2["elements"] ?? [])

            // Compare appState
            let appState1JSON = try JSONSerialization.data(withJSONObject: dict1["appState"] ?? [:])
            let appState2JSON = try JSONSerialization.data(withJSONObject: dict2["appState"] ?? [:])

            return elements1JSON == elements2JSON && appState1JSON == appState2JSON
        } catch {
            logger.error("Failed to compare excalidraw content: \(error)")
            return false
        }
    }

    private func applyExcalidrawFile(_ file: ExcalidrawFile?) {
        guard let file else { return }
        guard let currentContent = file.content else { return }

        // Check if content actually changed (compare elements and appState)
        if let lastContent = lastReceivedFileContent,
           compareExcalidrawContent(lastContent, currentContent) {
            // Content unchanged, don't update lastEditTime or cancel task
            logger.info("Content unchanged, skipping update")
            return
        }

        // Content changed, update tracking
        lastReceivedFileContent = currentContent
        lastEditTime = Date()
        logger.info("Content changed, updating lastEditTime and canceling any pending cloud sync task")

        // Cancel pending cloud sync task (user is editing again, need to reset wait)
        cloudSyncTask?.cancel()
        cloudSyncTask = nil

        // Apply local edits
        localFileBinding.wrappedValue = file
    }
}
