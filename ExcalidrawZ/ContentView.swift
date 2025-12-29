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

struct ContentView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var appPreference: AppPreference
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    let logger = Logger(label: "ContentView")
    
    @State private var hideContent: Bool = false
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var layoutState = LayoutState()
    @StateObject private var shareFileState = ShareFileState()

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isFirstImporting: Bool?
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
            .environmentObject(fileState)
            .environmentObject(exportState)
            .environmentObject(layoutState)
            .environmentObject(shareFileState)
            .modifier(DragStateModifier())
            .modifier(CoreDataMigrationModifier())
            .swiftyAlert(logs: true)
            .bindWindow($window)
            .containerSizeClassInjection()
            .onReceive(NotificationCenter.default.publisher(for: .shouldHandleImport)) { notification in
                handleImport(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .didOpenFromUrls)) { notification in
                handleOpenFromURLs(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { notification in
                handleToggleSidebar(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { notification in
                handleToggleInspector(notification)
            }
            .withContainerSize()
            .task { await prepare() }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ZStack {
            if isFirstImporting == nil {
                Color.clear
            } else if isFirstImporting == true {
                if #available(macOS 13.0, *) {
                    ICloudSyncingView(isFirstImporting: isFirstImporting)
                } else {
                    ICloudSyncingView(isFirstImporting: isFirstImporting)
                        .frame(width: 1150, height: 580)
                }
            } else if horizontalSizeClass == .regular {
                contentView()
                    .modifier(LibraryTrailingSidebarModifier())
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
    
    private func handleImport(_ notification: Notification) {
        guard let urls = notification.object as? [URL] else { return }
        if window?.isKeyWindow == true {
            Task.detached {
                do {
                    try await fileState.importFiles(urls)
                } catch {
                    await alertToast(error)
                    print("[handleImport] error: \(error)")
                }
            }
        }
    }
    
    private func handleOpenFromURLs(_ notification: Notification) {
        if let urls = notification.object as? [URL], !urls.isEmpty {
            fileState.temporaryFiles.append(contentsOf: urls)
            fileState.temporaryFiles = Array(Set(fileState.temporaryFiles))
            if fileState.currentActiveFile == nil || fileState.currentActiveGroup != .temporary {
                fileState.currentActiveGroup = .temporary
                fileState.setActiveFile(.localFile(fileState.temporaryFiles.first!))
            }
        }
    }
    
    private func handleToggleSidebar(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.isSidebarPresented.toggle()
    }
    private func handleToggleInspector(_ notification: Notification) {
        guard window?.isKeyWindow == true else { return }
        layoutState.isInspectorPresented.toggle()
    }
    
    // Check if it is first launch by checking the files count.
    private func prepare() async {
        do {
            guard !isICloudDisabled else {
                isFirstImporting = false
                try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                return
            }
            
            let isEmpty = try viewContext.fetch(NSFetchRequest<File>(entityName: "File")).isEmpty
            isFirstImporting = isEmpty
            if isFirstImporting == true, try await CKContainer.default().accountStatus() != .available {
                isFirstImporting = false
                return
            } else if !isEmpty {
                try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
            }
        } catch {
            alertToast(error)
        }
        
        self.cloudContainerEventChangeListener?.cancel()
        self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        ).sink { notification in
            if let userInfo = notification.userInfo {
                if let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event {
                    // On macOS, event.type will be `setup` only when first launched.
                    // On iOS, event.type will be `setup` every time it has been launched.
                    print("NSPersistentCloudKitContainer.eventChangedNotification: \(event.type), succeeded: \(event.succeeded)")
                    if event.type == .import, event.succeeded, isFirstImporting == true {
                        isFirstImporting = false
                        Task { @MainActor in
                            do {
                                try? await Task.sleep(nanoseconds: UInt64(2 * 1e+9))
                                try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                            } catch {
                                alertToast(error)
                            }
                        }
                        self.cloudContainerEventChangeListener?.cancel()
                    }
                }
            }
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
