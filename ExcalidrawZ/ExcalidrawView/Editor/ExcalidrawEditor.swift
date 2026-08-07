//
//  ExcalidrawEditor.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI
import Combine
import CoreData
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

import ChocofordUI
import Logging

enum EditorRoute: Hashable {
    case aiChat
}

struct ExcalidrawEditor: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize

    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState
    /// Drives the AI chat island overlay — its presentation toggle is global,
    /// but the *anchor* (bottom-center) is editor-local, hence the overlay
    /// lives here rather than at the NavigationSplitView level.
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
#if os(macOS)
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
#endif

    @ObservedObject private var cloudStorageConnections = CloudStorageConnectionStore.shared
    @ObservedObject private var cloudStorageDocumentStore = CloudStorageDocumentStore.shared

    let logger = Logger(label: "ExcalidrawEditor")

    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool

    @StateObject private var toolState = ToolState()

    @State private var isSettingsPresented = false
    @State private var excalidrawFile: ExcalidrawFile?
    @State private var isLoadingFile = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var cloudStorageRefreshTask: Task<Void, Never>?
    @State private var fileLoadRevealTask: Task<Void, Never>?
    @State private var recordVisitTask: Task<Void, Never>?
    @State private var documentLoadCompletion: ExcalidrawDocumentLoadCompletion?
    @State private var measuredNativeViewportInsets: ExcalidrawNativeViewportInsets = .zero
#if os(macOS)
    @State private var pendingCanvasFocusFileID: String?
#endif

    @State private var conflictFileURL: URL?
    @State private var cloudStorageConflictReference: CloudStorageDocumentReference?
    @State private var isCloudStorageConflictBlockingEditor = false
    @State private var isSyncing = false

    // MARK: - Smart Sync State

    /// Latest cloud data from observeExcalidrawFileStatus (not immediately applied)
    @State private var latestCloudData: Data?
    /// Last time the user edited the file (applyExcalidrawFile was called with actual changes)
    @State private var lastEditTime: Date?
    /// Task waiting to apply deferred cloud updates (cancellable)
    @State private var cloudSyncTask: Task<Void, Never>?
    /// Idle timeout in seconds before applying cloud updates
    private let idleTimeout: TimeInterval = 2.0
    private let recordVisitAfterOpenDelay: UInt64 = 1_000_000_000

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
            _ = persistCanvasUpdate(val)
        }
    }

    private enum CanvasUpdatePersistenceResult: Equatable {
        case accepted
        case ignoredNoChanges
        case rejected

        var shouldUpdateEditorState: Bool {
            switch self {
                case .accepted, .ignoredNoChanges:
                    return true
                case .rejected:
                    return false
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

    private var usesCompactIOSAIChatSurfaces: Bool {
#if os(iOS)
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
#else
        false
#endif
    }

    private var activeCloudStorageMetadataRevision: Int {
        guard case .cloudStorageFile(let reference) = activeFile else { return 0 }
        return cloudStorageDocumentStore.metadataRevision(for: reference.locationID)
    }

    private var activeCloudStorageMonitorID: String {
        guard scenePhase == .active,
              case .cloudStorageFile(let reference) = activeFile else {
            return "inactive"
        }
        return reference.id
    }

    private var activeCloudStorageConflictReference: CloudStorageDocumentReference? {
        guard case .cloudStorageFile(let reference) = activeFile,
              case .conflict = cloudStorageDocumentStore.syncState(for: reference) else {
            return nil
        }
        return reference
    }

    private var shouldFloatNavigationToolbarOverCanvas: Bool {
#if os(iOS)
        guard !usesCompactIOSAIChatSurfaces else { return false }
        return UIDevice.current.userInterfaceIdiom == .pad
#elseif os(macOS)
        true
#else
        false
#endif
    }

    private var canvasIgnoredSafeAreaEdges: Edge.Set {
        shouldFloatNavigationToolbarOverCanvas ? .top : []
    }

    private var nativeViewportInsetsForWeb: ExcalidrawNativeViewportInsets {
        shouldFloatNavigationToolbarOverCanvas ? measuredNativeViewportInsets : .zero
    }

#if os(macOS)
    private var shouldShowFloatingToolbarDragRegion: Bool {
        shouldFloatNavigationToolbarOverCanvas && activeFile != nil && !isLoadingFile
    }

    private var floatingToolbarDragRegionHeight: CGFloat {
        max(measuredNativeViewportInsets.top, 72)
    }
#endif
    
    
    @State private var canvasLoadingState: ExcalidrawCanvasView.LoadingState = .loading

    /// Live size of the editor's content frame. Fed into `AIChatIslandView`
    /// so it can clamp its drag offset back inside the editor when the user
    /// flings it past an edge.
    @State private var editorContentSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ExcalidrawCanvasView(
                    file: Binding {
                        localFileBinding.wrappedValue
                    } set: { val in
                        applyExcalidrawFile(val)
                    },
                    loadingState: $canvasLoadingState,
                    interactionEnabled: interactionEnabled && !isInCollaborationSpace,
                    onDocumentLoadFinished: { fileID in
                        documentLoadCompletion = ExcalidrawDocumentLoadCompletion(fileID: fileID)
                        revealLoadedFileAfterRender(fileID: fileID)
                    }
                ) { error in
                    alertToast(error)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .excalidrawEditorOverlays(
                    loadingState: $canvasLoadingState,
                    hasFile: localFileBinding.wrappedValue != nil,
                    keepsLoadingCoverPresented: isCloudStorageConflictBlockingEditor
                )
                .opacity(isInCollaborationSpace ? 0 : 1)
                .allowsHitTesting(!isInCollaborationSpace && !isLoadingFile)

                CollaborationEditorStack()
                    .opacity(isInCollaborationSpace ? 1 : 0)
                    .allowsHitTesting(isInCollaborationSpace && !isLoadingFile)
            }
            .environment(\.excalidrawNativeViewportInsets, nativeViewportInsetsForWeb)
            .allowsHitTesting(!isLoadingFile)
            .ignoresSafeArea(.container, edges: canvasIgnoredSafeAreaEdges)
#if os(iOS)
            .dismissKeyboardOnCanvasTap(isEnabled: layoutState.isCompactAIChatInputEditing)
#endif
            .background {
#if os(iOS)
                Color.clear
                    .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                        [FileHomeItemTransitionPreferenceID.viewportDestination: value]
                    }
#endif
            }

#if os(macOS)
            if shouldShowFloatingToolbarDragRegion {
                WindowDragRegion()
                    .frame(maxWidth: .infinity)
                    .frame(height: floatingToolbarDragRegionHeight)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
            }
#endif

            ExcalidrawTrailingControls()
                .opacity(isLoadingFile ? 0 : 1)
                .allowsHitTesting(!isLoadingFile)
        }
        .readSize($editorContentSize)
        .overlay(alignment: .bottom) {
#if os(iOS)
            if !usesCompactIOSAIChatSurfaces {
                AIChatIslandOverlay(canvasSize: editorContentSize)
            }
#else
            AIChatIslandOverlay(canvasSize: editorContentSize)
#endif
        }
#if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            if case .cloudStorageFile(let reference) = fileState.currentActiveFile {
                CloudStorageDocumentSyncIndicator(
                    reference: reference,
                    presentation: .canvas,
                    onConflictSelected: {
                        cloudStorageConflictReference = reference
                    }
                )
                .padding(.trailing, 8)
                .padding(.bottom, 18)
            }
        }
#endif
//#if DEBUG
//        .overlay(alignment: .bottomTrailing) {
//#if os(iOS)
//            if !usesCompactIOSAIChatSurfaces {
//                IndicatorOverlay()
//                    .padding(.trailing, 8)
//                    .ignoresSafeArea(.container, edges: .bottom)
//            }
//#else
//            IndicatorOverlay()
//                .padding(.trailing, 8)
//                .padding(.bottom, 18)
//#endif
//        }
//#endif
#if os(iOS)
        .overlay(alignment: .bottom) {
            CompactAIChatEditorOverlays()
        }
#endif
        .background {
            NativeViewportInsetsMeasurementView(
                insets: $measuredNativeViewportInsets
            )
        }
        .animation(.smooth(duration: 0.3), value: layoutState.isAIChatIslandMode)
        .animation(.smooth(duration: 0.3), value: layoutState.isCompactAIChatToolbarPresented)
        .animation(.smooth(duration: 0.3), value: layoutState.isCompactAIChatInputEditing)
        .modifier(
            LockedFileUnlockOverlayModifier(
                activeFile: activeFile,
                documentLoadCompletion: documentLoadCompletion,
                onPrepareLockedFile: prepareEditorForLockedFile,
                onApplyUnlockedContent: applyUnlockedFileContentToEditor
            )
        )
        .allowsHitTesting(interactionEnabled)
        .sheet(item: $cloudStorageConflictReference) { reference in
            CloudStorageConflictResolutionSheetView(
                reference: reference,
                onCancel: {
                    cancelCloudStorageConflictResolution(for: reference)
                }
            )
        }
        .observeExcalidrawFileStatus(
            for: activeFile,
            activeFileLockState: lockedContentState.activeFileLockState,
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
            activeFileLockState: lockedContentState.activeFileLockState,
            localFileBinding: localFileBinding
        ) { latestData in
            await MainActor.run {
                handleLatestData(latestData)
            }
        }
#endif
        // Cloud providers frequently refresh the active reference's name or
        // modified date. Those metadata-only replacements must not be treated
        // as a document switch and loaded into the WebView again.
        .watch(value: activeFile?.id) { _ in
            let newFile = activeFile
#if os(macOS)
            pendingCanvasFocusFileID = nil
#endif
            noteOpenTransitionStarted(for: newFile)
            loadingTask?.cancel()
            cloudStorageRefreshTask?.cancel()
            prepareCanvasLoadingPresentation(for: newFile)
            isCloudStorageConflictBlockingEditor = false
            loadingTask = Task {
                await lockedContentState.prepareForActiveFileChange(to: newFile)
                await loadExcalidrawFile(from: newFile)
            }
        }
#if os(macOS)
        .watch(value: fileHomeItemTransitionState.canShowItemContainerView) { isVisible in
            guard !isVisible else { return }
            focusPendingCanvasIfReady()
        }
#endif
        .watch(value: activeCloudStorageMetadataRevision) { _ in
            refreshActiveCloudStorageMetadata()
        }
        .watch(value: activeCloudStorageConflictReference, initial: true) { _, reference in
            guard let reference else { return }
            prepareEditorForCloudStorageConflict(reference)
        }
        .task(id: activeCloudStorageMonitorID) {
            guard scenePhase == .active,
                  case .cloudStorageFile(let reference) = activeFile else { return }
#if DEBUG
            logger.debug(
                "Monitoring active cloud document fileID=\(reference.id)"
            )
#endif
            await CloudStorageSyncService.shared.monitorActiveDocument(reference)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .activeCanvasFileDidRestore)
        ) { notification in
            guard let restoredFile = notification.object as? ExcalidrawFile,
                  activeFile?.id == restoredFile.id else {
                return
            }
            excalidrawFile = restoredFile
            lastEditTime = Date()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .cloudStorageConflictDidResolve)
        ) { notification in
            guard let result = notification.object as? CloudStorageConflictResolutionResult,
                  case .cloudStorageFile(let reference) = activeFile,
                  reference == result.reference else { return }

            cloudStorageConflictReference = nil
            loadingTask?.cancel()
            loadingTask = Task {
                do {
                    let activeFileID = reference.activeFileID
                    let resolvedFile = try await cloudStorageFile(
                        from: result.content,
                        fileID: activeFileID
                    )
                    await MainActor.run {
                        guard self.activeFile?.id == activeFileID else { return }
                        self.fileState.excalidrawWebCoordinator?.documentSyncController
                            .setTargetFileID(activeFileID)
                        self.beginFileLoadRevealGuard(fileID: activeFileID)
                        self.canvasLoadingState = .loading
                        self.isCloudStorageConflictBlockingEditor = false
                        self.excalidrawFile = resolvedFile
                    }
                } catch {
                    alertToast(error)
                }
            }
        }
        .watch(value: fileState.currentActiveFileIsInTrash) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .watch(value: layoutState.isAIChatIslandMode) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .watch(value: layoutState.isCompactAIChatToolbarPresented) { _ in
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
        }
        .task {
            noteOpenTransitionStarted(for: activeFile)
            prepareCanvasLoadingPresentation(for: activeFile)
            await lockedContentState.prepareForActiveFileChange(to: activeFile)
            await loadExcalidrawFile(from: activeFile)
        }
        .onAppear {
            collapseCompactAISurfacesIfCurrentFileIsTrashed()
            refreshActiveCloudStorageMetadata()
        }
        .onDisappear {
            recordVisitTask?.cancel()
            recordVisitTask = nil
            cloudStorageRefreshTask?.cancel()
            cloudStorageRefreshTask = nil
        }
        .modifier(ExcalidrawEditorToolbarModifier())
        .onReceive(NotificationCenter.default.publisher(for: .pencilInteractionModeDidChange)) { notification in
            guard let mode = notification.object as? ToolState.PencilInteractionMode else { return }
            Task {
                do {
                    try await toolState.setPencilInteractionMode(mode)
                } catch {
                    alertToast(error)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pencilPenModeChangeRequested)) { notification in
            guard let request = notification.object as? PencilPenModeChangeRequest else { return }
            Task {
                do {
                    try await toolState.togglePenMode(
                        enabled: request.enabled,
                        pencilConnected: request.pencilConnected
                    )
                } catch {
                    alertToast(error)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pencilPenModeStateRequested)) { _ in
            NotificationCenter.default.post(
                name: .pencilPenModeStateDidChange,
                object: toolState.inPenMode
            )
        }
        .watch(value: toolState.inPenMode, initial: true) { _, inPenMode in
            NotificationCenter.default.post(
                name: .pencilPenModeStateDidChange,
                object: inPenMode
            )
        }
        .environmentObject(toolState)
    }

    private func refreshActiveCloudStorageMetadata() {
        guard case .cloudStorageFile(let reference) = activeFile else { return }
        let latestReference = cloudStorageDocumentStore.latestReference(for: reference)
        guard latestReference.lastKnownName != reference.lastKnownName
                || latestReference.lastKnownModifiedAt != reference.lastKnownModifiedAt else {
#if DEBUG
            logger.debug(
                "Active cloud metadata unchanged itemID=\(reference.itemID.rawValue) name=\(reference.lastKnownName) revision=\(activeCloudStorageMetadataRevision)"
            )
#endif
            return
        }
#if DEBUG
        logger.debug(
            "Updating active cloud metadata itemID=\(reference.itemID.rawValue) name=\(reference.lastKnownName) -> \(latestReference.lastKnownName) revision=\(activeCloudStorageMetadataRevision)"
        )
#endif
        fileState.replaceCloudStorageDocumentReference(latestReference)
    }

    private func prepareCanvasLoadingPresentation(for file: FileState.ActiveFile?) {
        switch file {
            case .file, .localFile, .temporaryFile, .cloudStorageFile:
                canvasLoadingState = .loading
            case .collaborationFile, nil:
                break
        }
    }

    private func collapseCompactAISurfacesIfCurrentFileIsTrashed() {
        guard fileState.currentActiveFileIsInTrash else { return }
        layoutState.isAIChatIslandMode = false
        layoutState.exitCompactAIChatToolbar()
    }

    private func beginFileLoadRevealGuard(fileID: String) {
        fileLoadRevealTask?.cancel()
        isLoadingFile = true
        fileLoadRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled,
                  activeFile?.id == fileID else { return }
            isLoadingFile = false
            fileLoadRevealTask = nil
        }
    }

    private func revealLoadedFileAfterRender(fileID: String) {
        guard activeFile?.id == fileID else { return }
        let shouldFocusCanvas = isLoadingFile

        fileLoadRevealTask?.cancel()
        isLoadingFile = false
        fileLoadRevealTask = nil

#if os(macOS)
        if shouldFocusCanvas {
            pendingCanvasFocusFileID = fileID
            focusPendingCanvasIfReady()
        }
#endif
    }

#if os(macOS)
    private func focusPendingCanvasIfReady() {
        guard let fileID = pendingCanvasFocusFileID,
              interactionEnabled,
              activeFile?.id == fileID,
              !isLoadingFile,
              !fileHomeItemTransitionState.canShowItemContainerView,
              !isCloudStorageConflictBlockingEditor,
              let webView = fileState.excalidrawWebCoordinator?.webView else { return }

        // Apply the responder change after SwiftUI commits the hero transition's
        // hit-testing update. Until then the Home layer still owns keyboard focus.
        DispatchQueue.main.async {
            guard interactionEnabled,
                  activeFile?.id == fileID,
                  !isLoadingFile,
                  !fileHomeItemTransitionState.canShowItemContainerView,
                  !isCloudStorageConflictBlockingEditor else { return }
            let didFocus = webView.window?.makeFirstResponder(webView) == true
#if DEBUG
            let responderType = webView.window?.firstResponder.map {
                String(describing: type(of: $0))
            } ?? "nil"
            logger.debug(
                "Focused canvas after file open id=\(fileID) success=\(didFocus) responder=\(responderType)"
            )
#endif
            guard didFocus else { return }
            pendingCanvasFocusFileID = nil
        }
    }
#endif

    private func cancelFileLoadRevealGuard() {
        fileLoadRevealTask?.cancel()
        fileLoadRevealTask = nil
        isLoadingFile = false
    }

    private func noteOpenTransitionStarted(for file: FileState.ActiveFile?) {
        recordVisitTask?.cancel()
        recordVisitTask = nil

        guard let file else {
            return
        }

        scheduleVisitRecordAfterOpenDelay(fileID: file.id)
    }

    private func scheduleVisitRecordAfterOpenDelay(fileID: String) {
        recordVisitTask?.cancel()

        recordVisitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: recordVisitAfterOpenDelay)
            guard !Task.isCancelled,
                  activeFile?.id == fileID else { return }

            fileState.recordVisitAfterFileReady(fileID: fileID)
            recordVisitTask = nil
        }
    }
    
    private func loadExcalidrawFile(from activeFile: FileState.ActiveFile?) async {
        guard let activeFile else {
            cancelFileLoadRevealGuard()
            self.excalidrawFile = nil
            fileState.excalidrawWebCoordinator?.documentSyncController.resetFileLoadState()
            return
        }

        if case .cloudStorageFile(let reference) = activeFile,
           case .conflict = cloudStorageDocumentStore.syncState(for: reference) {
            prepareEditorForCloudStorageConflict(reference)
            return
        }

        switch activeFile {
            case .file(_), .localFile(_), .temporaryFile(_), .cloudStorageFile(_):
                fileState.excalidrawWebCoordinator?.documentSyncController
                    .setTargetFileID(activeFile.id)
                beginFileLoadRevealGuard(fileID: activeFile.id)
                canvasLoadingState = .loading
            default:
                cancelFileLoadRevealGuard()
                fileState.excalidrawWebCoordinator?.documentSyncController.resetFileLoadState()
        }
        
        do {
            switch activeFile {
                case .file(let file):
                    let content = try await file.loadContent(applyingLocalViewport: true)
                    let parsedFile = try? ExcalidrawFile(data: content, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = parsedFile
                    }
                    
                case .localFile(let url):
                    let data = try await FileSyncCoordinator.shared.openFile(url)
                    let file = try ExcalidrawFile(data: data, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = file
                    }

                case .temporaryFile(let url):
                    let data = try await FileSyncCoordinator.shared.openFile(url)
                    let file = try ExcalidrawFile(data: data, id: activeFile.id)
                    await MainActor.run {
                        guard self.activeFile?.id == activeFile.id else { return }
                        self.excalidrawFile = file
                    }

                case .cloudStorageFile(let reference):
                    try await loadCloudStorageFile(
                        reference,
                        activeFile: activeFile
                    )

                default:
                    await MainActor.run {
                        self.excalidrawFile = nil
                    }
            }
        } catch EncryptedContentError.contentLocked(_, _) {
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                cancelFileLoadRevealGuard()
                prepareEditorForLockedFile()
            }
        } catch is EncryptedContentError {
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                cancelFileLoadRevealGuard()
                lockedContentState.markUnlockFailed(fileID: activeFile.id)
                prepareEditorForLockedFile()
            }
        } catch {
            fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
            alertToast(error)
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                cancelFileLoadRevealGuard()
                self.excalidrawFile = nil
                self.canvasLoadingState = .error(error)
            }
        }
    }

    private func loadCloudStorageFile(
        _ reference: CloudStorageDocumentReference,
        activeFile: FileState.ActiveFile
    ) async throws {
        let store = CloudStorageDocumentStore.shared
        let cachedContent = try store.cachedContent(for: reference)
        let cachedFile: ExcalidrawFile?

        do {
            if let cachedContent {
                cachedFile = try await cloudStorageFile(
                    from: cachedContent,
                    fileID: activeFile.id
                )
                await MainActor.run {
                    guard self.activeFile?.id == activeFile.id else { return }
                    self.excalidrawFile = cachedFile
                }
            } else {
                cachedFile = nil
            }
        } catch {
            cachedFile = nil
            try? store.discardCachedContent(for: reference)
            logger.warning(
                "Failed to open cached cloud document; falling back to provider: \(cloudStorageDocumentStore.displayName(for: reference)), error=\(error)"
            )
        }

        if let cachedFile {
            scheduleCloudStorageRefresh(
                reference,
                activeFile: activeFile,
                cachedFile: cachedFile
            )
            return
        }

        do {
            let refreshedContent = try await store.content(
                for: reference,
                checkingRemoteRevision: true
            )
            let refreshedFile = try await cloudStorageFile(
                from: refreshedContent,
                fileID: activeFile.id
            )
            await MainActor.run {
                guard self.activeFile?.id == activeFile.id else { return }
                self.excalidrawFile = refreshedFile
            }
        } catch {
            throw error
        }
    }

    private func scheduleCloudStorageRefresh(
        _ reference: CloudStorageDocumentReference,
        activeFile: FileState.ActiveFile,
        cachedFile: ExcalidrawFile
    ) {
        cloudStorageRefreshTask?.cancel()
        cloudStorageRefreshTask = Task {
            let store = CloudStorageDocumentStore.shared
            do {
                guard let candidate = try await store.remoteContentCandidate(for: reference) else {
                    return
                }
                guard !Task.isCancelled else {
                    store.markLocal(for: reference)
                    return
                }
                let refreshedFile = try await cloudStorageFile(
                    from: candidate.data,
                    fileID: activeFile.id
                )
                guard !Task.isCancelled else {
                    store.markLocal(for: reference)
                    return
                }

                await MainActor.run {
                    guard self.activeFile?.id == activeFile.id,
                          let currentFile = self.excalidrawFile else {
                        store.markLocal(for: reference)
                        return
                    }
                    guard !self.hasPersistentCanvasChanges(
                        in: currentFile,
                        comparedTo: cachedFile
                    ) else {
                        self.logger.info(
                            "Skipped refreshed cloud document because the local canvas changed: \(cloudStorageDocumentStore.displayName(for: reference))"
                        )
                        store.markConflict(for: reference)
                        return
                    }

                    do {
                        guard try store.installRemoteContentCandidate(candidate, for: reference) else {
                            return
                        }
                        self.excalidrawFile = refreshedFile
                    } catch {
                        store.reportSyncFailure(
                            error,
                            operation: .download,
                            for: reference
                        )
                        self.logger.warning(
                            "Failed to install refreshed cloud document: \(cloudStorageDocumentStore.displayName(for: reference)), error=\(error)"
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                store.reportSyncFailure(
                    error,
                    operation: .download,
                    for: reference
                )
                logger.warning(
                    "Cloud refresh failed; continuing with cached document: \(cloudStorageDocumentStore.displayName(for: reference)), error=\(error)"
                )
            }
        }
    }

    private func cloudStorageFile(
        from content: Data,
        fileID: String
    ) async throws -> ExcalidrawFile {
        let content = try await ExcalidrawViewportStateStore.shared
            .contentDataByApplyingStoredViewport(
                to: content,
                fileID: fileID
            )
        return try ExcalidrawFile(data: content, id: fileID)
    }

    @MainActor
    private func prepareEditorForCloudStorageConflict(
        _ reference: CloudStorageDocumentReference
    ) {
        cancelFileLoadRevealGuard()
        cloudStorageRefreshTask?.cancel()
        cloudStorageRefreshTask = nil
        fileState.excalidrawWebCoordinator?.documentSyncController.resetFileLoadState()
        excalidrawFile = nil
        canvasLoadingState = .loading
        isLoadingFile = true
        isCloudStorageConflictBlockingEditor = true
        cloudStorageConflictReference = reference
    }

    @MainActor
    private func cancelCloudStorageConflictResolution(
        for reference: CloudStorageDocumentReference
    ) {
        guard case .cloudStorageFile(let activeReference) = activeFile,
              activeReference == reference else { return }

        loadingTask?.cancel()
        cloudStorageRefreshTask?.cancel()
        fileState.excalidrawWebCoordinator?.documentSyncController.resetFileLoadState()
        cloudStorageConflictReference = nil
        fileState.discardAndCloseActiveFile()
    }

    @MainActor
    private func prepareEditorForLockedFile() {
        fileState.excalidrawWebCoordinator?.documentSyncController.setTargetFileID(nil)
        cloudSyncTask?.cancel()
        cloudSyncTask = nil
        latestCloudData = nil
        excalidrawFile = nil
    }

    private func applyUnlockedFileContentToEditor(
        _ content: Data,
        request: LockedFileUnlockRequest
    ) async throws {
        let parsedFile = try ExcalidrawFile(data: content, id: request.fileID)
        await MainActor.run {
            guard self.activeFile?.id == request.fileID else { return }
            self.fileState.excalidrawWebCoordinator?.documentSyncController
                .setTargetFileID(request.fileID)
            self.excalidrawFile = parsedFile
        }
    }
    
    private func handleLatestData(_ latestData: Data) {
        guard lockedContentState.activeFileLockState != .locked else {
            logger.info("Ignored cloud update while active file is locked")
            return
        }

        // Check if user has been idle long enough
        let isIdle = if let lastEdit = latestLocalCanvasEditTime() {
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
                if let lastEdit = await MainActor.run(body: { self.latestLocalCanvasEditTime() }),
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

    private func latestLocalCanvasEditTime() -> Date? {
        let mutationDate = fileState.recentLocalCanvasMutationDate(for: activeFile)
        switch (lastEditTime, mutationDate) {
            case (.some(let lastEdit), .some(let mutation)):
                return max(lastEdit, mutation)
            case (.some(let lastEdit), .none):
                return lastEdit
            case (.none, .some(let mutation)):
                return mutation
            case (.none, .none):
                return nil
        }
    }

    private func pullUpdatingFromCloud(latestData: Data) async {
        guard lockedContentState.activeFileLockState != .locked else {
            self.logger.info("Skipped cloud pull while active file is locked")
            return
        }

        self.logger.info("pullUpdatingFromCloud")
        do {
            let data: Data
            if let activeFile,
               case .file = activeFile,
               let fileID = excalidrawFile?.id {
                data = try await ExcalidrawViewportStateStore.shared
                    .contentDataByApplyingStoredViewport(
                        to: latestData,
                        fileID: fileID
                    )
            } else {
                data = latestData
            }
            let file = try ExcalidrawFile(data: data, id: excalidrawFile?.id)
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

    private func hasPersistentCanvasChanges(
        in file: ExcalidrawFile,
        comparedTo currentFile: ExcalidrawFile
    ) -> Bool {
        if let content = file.content,
           let currentContent = currentFile.content {
            return content != currentContent
        }

        return file.elements != currentFile.elements || file.appState != currentFile.appState
    }

    private func applyExcalidrawFile(_ file: ExcalidrawFile?) {
        guard let file else { return }

        if let currentFile = excalidrawFile {
            let hasChanges = hasPersistentCanvasChanges(in: file, comparedTo: currentFile)
            guard hasChanges else {
                return
            }
        }

        let persistenceResult = persistCanvasUpdate(file)
        guard persistenceResult.shouldUpdateEditorState else { return }

        if persistenceResult == .accepted {
            // Content changed, update tracking
            lockedContentState.noteUserActivity()
            lastEditTime = Date()

            // Cancel pending cloud sync task (user is editing again, need to reset wait)
            cloudSyncTask?.cancel()
            cloudSyncTask = nil
        }

        // Keep in-memory file in sync so exports read the latest elements.
        excalidrawFile = file
    }

    private func persistCanvasUpdate(_ file: ExcalidrawFile) -> CanvasUpdatePersistenceResult {
        guard activeFile?.id == file.id else {
            logger.debug(
                "Rejected canvas update: target mismatch file=\(file.id) active=\(activeFile?.id ?? "nil")"
            )
            return .rejected
        }

        // Block updates while loading new file.
        guard !isLoadingFile else {
            logger.debug("Rejected canvas update: file loading id=\(file.id)")
            return .rejected
        }

        guard lockedContentState.activeFileLockState != .locked else {
            logger.debug("Rejected canvas update: active file locked id=\(file.id)")
            return .rejected
        }

        switch activeFile {
            case .file(let activeFile):
                if let currentFile = excalidrawFile,
                   !hasPersistentCanvasChanges(in: file, comparedTo: currentFile) {
                    logger.debug("Ignored canvas update: no persistent changes id=\(file.id)")
                    return .ignoredNoChanges
                }
                logger.debug("Mirroring library canvas update id=\(activeFile.id?.uuidString ?? file.id) elements=\(file.elements.count)")
                return .accepted

            case .localFile(let url):
                guard case .localFolder(let folder) = fileState.currentActiveGroup else { return .rejected }
                logger.debug("Persisting local canvas update id=\(file.id) url=\(url.lastPathComponent) elements=\(file.elements.count)")
                Task {
                    try folder.withSecurityScopedURL { _ in
                        do {
                            let oldFile = try ExcalidrawFile(contentsOf: url)
                            if !hasPersistentCanvasChanges(in: file, comparedTo: oldFile) {
                                return
                            }
                            try await fileState.updateLocalFile(
                                to: url,
                                with: file,
                                context: viewContext
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                return .accepted

            case .temporaryFile(let url):
                logger.debug("Persisting temporary canvas update id=\(file.id) url=\(url.lastPathComponent) elements=\(file.elements.count)")
                Task {
                    do {
                        let oldFile = try ExcalidrawFile(contentsOf: url)
                        if !hasPersistentCanvasChanges(in: file, comparedTo: oldFile) {
                            return
                        }
                        try await fileState.updateLocalFile(
                            to: url,
                            with: file,
                            context: viewContext
                        )
                    } catch {
                        alertToast(error)
                    }
                }
                return .accepted

            case .cloudStorageFile(let reference):
                if case .conflict = cloudStorageDocumentStore.syncState(for: reference) {
                    logger.debug(
                        "Rejected canvas update while cloud conflict is unresolved id=\(file.id)"
                    )
                    return .rejected
                }
                if let currentFile = excalidrawFile,
                   !hasPersistentCanvasChanges(in: file, comparedTo: currentFile) {
                    return .ignoredNoChanges
                }
                logger.debug(
                    "Persisting cloud storage canvas update id=\(file.id) name=\(cloudStorageDocumentStore.displayName(for: reference)) elements=\(file.elements.count)"
                )
                Task {
                    do {
                        var file = file
                        try file.updateContentFilesFromFiles()
                        guard var content = file.content else { return }
                        content = try await ExcalidrawViewportStateStore.shared
                            .contentDataBySeparatingViewport(
                                from: content,
                                fileID: file.id
                            )
                        try await fileState.updateCloudStorageFile(
                            reference,
                            content: content
                        )
                    } catch {
                        alertToast(error)
                    }
                }
                return .accepted

            default:
                return .rejected
        }
    }
}

private struct NativeViewportInsetsMeasurementView: View {
    @Binding var insets: ExcalidrawNativeViewportInsets

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(
                proxy.safeAreaInsets.top,
                proxy.frame(in: .global).minY
            )
            let measuredInsets = ExcalidrawNativeViewportInsets(top: topInset)

            Color.clear
                .allowsHitTesting(false)
                .watch(value: measuredInsets, initial: true) { _, newValue in
                    guard insets != newValue else { return }
                    insets = newValue
                }
        }
        .allowsHitTesting(false)
    }
}

#if os(macOS)
private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
#endif

#if os(iOS)
private extension View {
    func dismissKeyboardOnCanvasTap(isEnabled: Bool) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                guard isEnabled else { return }
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
#endif
