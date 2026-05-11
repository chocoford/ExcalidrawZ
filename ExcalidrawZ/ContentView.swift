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
import Logging

import ChocofordUI
import ChocofordEssentials
import SwiftyAlert
import SFSafeSymbols
import LLMKit

struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var appPreference: AppPreference
    /// Pulled from the app-level environment (see `ExcalidrawZApp`).
    /// Both are needed here because we trigger conversation
    /// pre-selection on every active-file change (see the
    /// `.task(id:)` below) — the inspector / island panels then just
    /// read the already-pinned `aiChatConversationID` instead of
    /// each having to refresh on appear.
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    let logger = Logger(label: "ContentView")
    
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
    
    @State private var isFirstAppear = true
    
    var body: some View {
        content()
            .navigationTitle("")
            .modifier(PrintModifier())
            .modifier(WhatsNewSheetViewModifier())
            .modifier(NewRoomModifier())
            .modifier(PaywallModifier())
            .modifier(SearchableModifier())
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .modifier(OpenFromURLModifier())
            .modifier(UserActivityHandlerModifier())
            .modifier(ShareFileModifier())
            .modifier(LocalFolderMonitorModifier())
            .modifier(PDFViewerModifier())
            .modifier(MenuBarImportHandlerModifier())
            .environmentObject(fileState)
            .environmentObject(exportState)
            .environmentObject(layoutState)
            .environmentObject(shareFileState)
            .environmentObject(canvasPreferencesState)
            .modifier(DragStateModifier())
            .modifier(StartupSyncModifier())
            .modifier(CoreDataMigrationModifier())
            .modifier(ActiveFileSwitchBlockedToastModifier(fileState: fileState))
            .swiftyAlert(logs: true)
            .bindWindow($window)
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
            .onChange(of: fileState.currentActiveFile) { newValue in
                // Going back to Home: nothing to inspect, so collapse the panel.
                if newValue == nil, layoutState.isInspectorPresented {
                    layoutState.isInspectorPresented = false
                }
            }
            // Pre-load the chat conversation tied to the active file
            // *as soon as the file changes*, not lazily when the user
            // opens the chat panel. The id-based `.task` fires on
            // first appear and on every subsequent change — empty
            // ActiveFile keeps the previous selection nil, so the
            // panel still opens with a clean slate when no file is
            // loaded. Multi-conversation per file isn't surfaced in
            // the UI yet (single-thread feel), but the persistence
            // layer is already file-scoped, so this is just picking
            // the latest from that file's bin.
            .task(id: fileState.currentActiveFile?.id) {
                print("[AIChatDiag] ContentView.task(id:) fired with id=\(fileState.currentActiveFile?.id ?? "nil")")
                await aiChatState.loadConversationForActiveFile(
                    in: llmState,
                    fileState: fileState
                )
            }
            .withContainerSize()
            .task { await prepare() }
    }
    
    @MainActor @ViewBuilder
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
    
    @MainActor @ViewBuilder
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
    
    // Check if it is first launch by checking the files count.
    private func prepare() async {
        self.cloudContainerEventChangeListener?.cancel()
        self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        ).sink { notification in
            Task {
                try? await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
            }
        }
    }
}

private struct ActiveFileSwitchBlockedToastModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @ObservedObject var fileState: FileState

    func body(content: Content) -> some View {
        content
            .onChange(of: fileState.activeFileSwitchBlockedToken) { _ in
                showToast()
            }
    }

    private func showToast() {
        switch fileState.activeFileSwitchBlockedReason {
            case .aiGenerationInProgress:
                alertToast(.init(
                    displayMode: .hud,
                    type: .regular,
                    title: String(localized: "Stop AI generation before switching files or spaces.")
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
