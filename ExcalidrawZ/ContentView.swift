//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import CoreData
import CloudKit
import Combine

import ChocofordUI
import ChocofordEssentials
import SwiftyAlert
import SFSafeSymbols
import LLMKit

struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appPreference: AppPreference
    /// Pulled from the app-level environment (see `ExcalidrawZApp`).
    /// Both are needed here because we trigger conversation
    /// pre-selection on every active-file change (see the
    /// `.task(id:)` below) — the inspector / island panels then just
    /// read the already-pinned `aiChatConversationID` instead of
    /// each having to refresh on appear.
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared
    @ObservedObject private var cloudStorageConnections = CloudStorageConnectionStore.shared
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    @State private var hideContent: Bool = false
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var layoutState = LayoutState()
    @StateObject private var shareFileState = ShareFileState()
    @StateObject private var canvasPreferencesState = CanvasPreferencesState()

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var cloudContainerEventChangeListener: AnyCancellable?
    @State private var cloudContainerImportCleanupTask: Task<Void, Never>?
    
    @State private var isFirstAppear = true

    private static let activeFileCloseInspectorDismissalDelay: UInt64 = 400_000_000
    private static let cloudKitImportSettleDelay: UInt64 = 4_000_000_000
    
    var body: some View {
        content()
            .navigationTitle("")
            .modifier(PrintModifier())
            .modifier(WhatsNewSheetViewModifier())
            .modifier(NewRoomModifier())
            .modifier(StoreKitEntitlementRefreshModifier())
            .modifier(PaywallModifier())
            .modifier(SettingsSheetPresentationModifier())
            .modifier(SearchableModifier())
            .modifier(OpenFromURLModifier())
            .modifier(UserActivityHandlerModifier())
            .modifier(ShareFileModifier())
            .modifier(LocalFolderMonitorModifier())
            .modifier(PDFViewerModifier())
            .modifier(MenuBarImportHandlerModifier())
            .modifier(DragStateModifier())
            .modifier(StartupSyncModifier())
            .modifier(CoreDataMigrationModifier())
            .modifier(ActiveFileSwitchBlockedToastModifier(fileState: fileState))
            .environmentObject(fileState)
            .environmentObject(exportState)
            .environmentObject(layoutState)
            .environmentObject(shareFileState)
            .environmentObject(canvasPreferencesState)
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .swiftyAlert(logs: true)
            .bindWindow($window)
#if os(macOS)
            .task(id: window?.windowNumber) {
                guard let window else { return }
                ScreenAnnotationController.shared.register(
                    fileState: fileState,
                    for: window
                )
            }
#endif
            .containerSizeClassInjection()
            .onReceive(NotificationCenter.default.publisher(for: .didOpenFromUrls)) { notification in
                handleOpenFromURLs(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { notification in
                handleToggleSidebar(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { notification in
                handleToggleInspector(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .cloudStorageItemIdentityDidChange
                )
            ) { notification in
                guard let change = notification.object as? CloudStorageItemIdentityChange else {
                    return
                }
                fileState.applyCloudStorageIdentityChange(change)
            }
            .modifier(LockedContentEventModifier(fileState: fileState))
            .modifier(ActiveFileAvailabilityModifier(fileState: fileState))
            .watch(value: fileState.currentActiveFile) { newValue in
                // Going back to Home: nothing to inspect, so collapse the panel.
                if newValue == nil, layoutState.isInspectorPresented {
                    layoutState.isInspectorPresented = false
                }
            }
            .watch(value: aiChatPreferences.isAIEnabled) { isEnabled in
                if isEnabled {
                    Task {
                        await llmState.refreshConversations()
                    }
                } else {
                    cancelActiveAIGenerationForDisabledAI()
                }
            }
            .watch(value: colorScheme) { newValue in
                FileCoverCacheCoordinator.shared.scheduleRecentCoverPrewarm(colorScheme: newValue)
            }
            .watch(value: lockedContentState.filePreviewLockStateRevision) { _ in
                FileCoverCacheCoordinator.shared.refreshLibraryCoversForLockStateChange(
                    colorScheme: colorScheme
                )
            }
            .task(id: connectedCloudStorageLocationIDs) {
                await fileState.reconcileCloudStorageLocations(
                    connectedCloudStorageLocationIDs
                )
            }
            // Pre-select the chat conversation tied to the active file
            // without restoring the full LLM conversation cache. The id-based
            // `.task` fires on first appear and on every subsequent change;
            // AI surfaces restore message content lazily when they appear.
            // This keeps file transitions away from historical attachment IO.
            .task(id: fileState.currentActiveFile?.id) {
                let activeFileID = fileState.currentActiveFile?.id
                if activeFileID != nil {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled,
                          fileState.currentActiveFile?.id == activeFileID else { return }
                }
                await aiChatState.loadConversationForActiveFile(
                    fileState: fileState
                )
            }
            .withContainerSize()
            .task {
#if os(macOS)
                await MainActor.run {
                    ApplicationTerminationCanvasFlushCoordinator.shared.register(fileState: fileState)
                }
#endif
                await MainActor.run {
                    fileState.prepareActiveFileCloseTransition = {
                        guard layoutState.isInspectorPresented else { return }
                        layoutState.isInspectorPresented = false
                        try? await Task.sleep(nanoseconds: Self.activeFileCloseInspectorDismissalDelay)
                    }
                    ExcalidrawMCPAppBridge.shared.register(
                        fileState: fileState,
                        context: viewContext
                    )
                    FileCoverCacheCoordinator.shared.register(
                        fileState: fileState,
                        lockedContentState: lockedContentState,
                        context: viewContext
                    )
                    LibraryItemPreviewCoordinator.shared.register(fileState: fileState)
                    FileCoverCacheCoordinator.shared.scheduleRecentCoverPrewarm(colorScheme: colorScheme)
                }
                await prepare()
            }
    }

    private var connectedCloudStorageLocationIDs: Set<UUID> {
        Set(cloudStorageConnections.locations.map(\.id))
    }
    
    @ViewBuilder
    private func content() -> some View {
        ZStack {
            if horizontalSizeClass == .regular {
                contentView()
                    .modifier(InspectorPresentationModifier())
            } else {
                // Compact uses TabView, can not use library here.
                contentView()
            }
        }
    }
    
    @ViewBuilder
    private func contentView() -> some View {
        if #available(macOS 13.0, *),
            appPreference.sidebarLayout == .sidebar {
            ContentViewModern()
        } else {
            ContentViewLagacy()
        }
    }
    
    private func handleOpenFromURLs(_ notification: Notification) {
        if let urls = notification.object as? [URL], !urls.isEmpty {
            fileState.temporaryFiles.append(contentsOf: urls)
            fileState.temporaryFiles = Array(Set(fileState.temporaryFiles))
            if fileState.currentActiveFile == nil || fileState.currentActiveGroup != .temporary {
                fileState.setActiveFile(
                    .localFile(fileState.temporaryFiles.first!)
                )
            }
        }
    }
    
    private func handleToggleSidebar(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.isSidebarPresented.toggle()
    }
    private func handleToggleInspector(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.toggleInspector()
    }

    @MainActor
    private func cancelActiveAIGenerationForDisabledAI() {
        if let conversationID = fileState.aiChatConversationID {
            llmState.cancelGeneration(conversationID: conversationID)
            aiChatState.markGenerationCancelled(conversationID: conversationID)
            aiChatState.unmarkCompacting(conversationID: conversationID)
        }
        aiChatState.pendingQueue.removeAll()
        aiChatState.cancelEditing(conversationID: fileState.aiChatConversationID)
    }
    
    // Check if it is first launch by checking the files count.
    private func prepare() async {
        self.cloudContainerEventChangeListener?.cancel()
        self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        ).sink { notification in
            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import,
                  event.succeeded else {
                return
            }

            Task { @MainActor in
                cloudContainerImportCleanupTask?.cancel()
                cloudContainerImportCleanupTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.cloudKitImportSettleDelay)
                    guard !Task.isCancelled else { return }
                    try? await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                }
            }
        }

        try? await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
    }
}

private struct ActiveFileSwitchBlockedToastModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @ObservedObject var fileState: FileState

    func body(content: Content) -> some View {
        content
            .watch(value: fileState.activeFileSwitchBlockedToken) { _ in
                showToast()
            }
    }

    private func showToast() {
        switch fileState.activeFileSwitchBlockedReason {
            case .aiGenerationInProgress:
                alertToast(.init(
                    displayMode: .hud,
                    type: .regular,
                    title: String(localizable: .aiChatActiveFileSwitchBlockedToastTitle)
                ))
            case nil:
                break
        }
    }
}

#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
#endif
