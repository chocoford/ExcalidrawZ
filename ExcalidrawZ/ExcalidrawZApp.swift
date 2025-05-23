//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import os.log
#if os(macOS)
import ServiceManagement
#endif

import SwiftyAlert
import ChocofordUI
#if os(macOS) && !APP_STORE
import Sparkle
#endif

extension Notification.Name {
    static let shouldHandleImport = Notification.Name("ShouldHandleImport")
    static let didImportToExcalidrawZ = Notification.Name("DidImportToExcalidrawZ")
    static let toggleWhatsNewSheet = Notification.Name("ToggleWhatsNewSheet")
    static let togglePrintModalSheet = Notification.Name("TogglePrintModalSheet")
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let toggleInspector = Notification.Name("ToggleInspector")
    static let toggleShare = Notification.Name("ToggleShare")
}

@main
@MainActor
struct ExcalidrawZApp: App {
    @Environment(\.managedObjectContext) private var viewContext
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
        
#if os(macOS) && !APP_STORE
    private let updaterController: SPUStandardUpdaterController
#endif
    init() {
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
#if os(macOS) && !APP_STORE
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
#endif
        
        // Setting Folder Structure Type
        if #available(macOS 13.0, *) {} else {
            UserDefaults.standard.set(1, forKey: "FolderStructureStyle")
        }
        
        // refresh spotlight index if expiration
        var shouldRefreshSpotlightIndex = false
        let dateString = UserDefaults.standard.string(forKey: "LastSpotlightIndexRefreshTime")
        if let dateString,
           let date = try? Date(dateString, strategy: .iso8601),
           date < Date.now - 20 * 24 * 60 * 60 {
            shouldRefreshSpotlightIndex = true
        } else if dateString == nil {
            shouldRefreshSpotlightIndex = true
        }
        if shouldRefreshSpotlightIndex {
            Task {
                do {
                    try await PersistenceController.shared.refreshIndices()
                    UserDefaults.standard.set(Date.now.formatted(.iso8601), forKey: "LastSpotlightIndexRefreshTime")
                } catch {
                    print(error)
                }
            }
        }
    }
    // Can not run agent in a sandboxed app.
    // let service = SMAppService.agent(plistName: "com.chocoford.excalidraw.ExcalidrawServer.agent.plist")
    
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appPrefernece = AppPreference()
    @StateObject private var store = Store()
#if os(macOS) && !APP_STORE
    @StateObject private var updateChecker = UpdateChecker()
#endif
    
    let server = ExcalidrawServer()
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExcalidrawApp")
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .environmentObject(store)
                .onAppear {
#if os(macOS) && !APP_STORE
                    updateChecker.assignUpdater(updater: updaterController.updater)
#endif
                }
        }
        .onChange(of: scenePhase) { newValue in
            logger.info("On scene phase changed: \(String(describing: newValue), privacy: .public)")
        }
        // prevent window being open by urls.
        .handlesExternalEvents(matching: ["*"])

#if os(macOS) && !APP_STORE
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(checkForUpdatesViewModel: updateChecker)
            }
        }
#endif
#if os(macOS)
        .defaultSizeIfAvailable(CGSize(width: 1200, height: 700))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleNewDraw,
                        object: nil
                    )
                } label: {
                    Text(.localizable(.createNewFile))
                }
                .keyboardShortcut("N", modifiers: .command)
                
                Button {
                    NotificationCenter.default.post(
                        name: .shouldHandleNewDrawFromClipboard,
                        object: nil
                    )
                } label: {
                    Text(.localizable(.whatsNewNewDrawFromClipboardTitle))
                }
                .keyboardShortcut("N", modifiers: [.command, .option, .shift])
                
//                Divider()
                
//                Button("New Window") {
//                    // openWindow(id: "Some ID")
//                }
//                .keyboardShortcut("N", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .printItem) {
                Button {
                    NotificationCenter.default.post(name: .togglePrintModalSheet, object: nil)
                } label: {
                    Text(.localizable(.menubarButtonPrint))
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            CommandGroup(after: .importExport) {
                Button {
                    let panel = ExcalidrawOpenPanel.importPanel
                    if panel.runModal() == .OK {
                        NotificationCenter.default.post(name: .shouldHandleImport, object: panel.urls)
                    }
                } label: {
                    Text(.localizable(.menubarButtonImport))
                }
                Button {
                    try? archiveAllFiles(context: viewContext)
                } label: {
                    Text(.localizable(.menubarButtonExportAll))
                }
            }
            
            // MARK: View
            CommandGroup(before: .sidebar) {
                Button {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleSidebar))
                }
                .keyboardShortcut("0", modifiers: [.command])
                
                Button {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleLibrary))
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                
                Button {
                    NotificationCenter.default.post(name: .toggleShare, object: nil)
                } label: {
                    Text(.localizable(.menubarToggleShare))
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .help) {
                Button {
                    NotificationCenter.default.post(name: .toggleWhatsNewSheet, object: nil)
                } label: {
                    Text(.localizable(.whatsNewTitle))
                }
            }
        }
#endif
        
#if os(macOS)
        // documentGroup()

        Settings {
            SettingsView()
                .swiftyAlert(logs: true)
                .containerSizeClassInjection()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .environmentObject(store)
#if !APP_STORE
                .environmentObject(updateChecker)
#endif
        }
#endif
    }
    
    
#if os(macOS)
    @MainActor
    private func documentGroup() -> some Scene {
        if #available(macOS 13.0, iOS 17.0, *) {
            return DocumentGroup(newDocument: ExcalidrawFile()) { config in
                SingleEditorView(config: config, shouldAdjustWindowSize: false)
                    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                    .swiftyAlert()
                    .environmentObject(appPrefernece)
            }
            .defaultSize(width: 1200, height: 600)
        } else {
            return DocumentGroup(newDocument: ExcalidrawFile()) { config in
                SingleEditorView(config: config, shouldAdjustWindowSize: true)
                    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                    .swiftyAlert()
                    .environmentObject(appPrefernece)
                
            }
        }
    }
#endif
}

fileprivate extension Scene {
    func defaultSizeIfAvailable(_ size: CGSize) -> some Scene {
        if #available(macOS 13.0, iOS 17.0, *) {
            return self.defaultSize(size)
        }
        else {
            return self
        }
    }
}
