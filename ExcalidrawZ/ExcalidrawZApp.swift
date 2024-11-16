//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
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
}

@main
@MainActor
struct ExcalidrawZApp: App {
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
    }
    // Can not run agent in a sandboxed app.
    // let service = SMAppService.agent(plistName: "com.chocoford.excalidraw.ExcalidrawServer.agent.plist")
    
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appPrefernece = AppPreference()
#if os(macOS) && !APP_STORE
    @StateObject private var updateChecker = UpdateChecker()
#endif
    let server = ExcalidrawServer()
        
    var body: some Scene {
        WindowGroup {
            RootView()
                .swiftyAlert()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .onAppear {
#if os(macOS) && !APP_STORE
                    updateChecker.assignUpdater(updater: updaterController.updater)
#endif
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "MainWindowGroup"))
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
            CommandGroup(after: .importExport) {
                Button {
                    let panel = ExcalidrawOpenPanel.importPanel
                    if panel.runModal() == .OK {
                        NotificationCenter.default.post(name: .shouldHandleImport, object: panel.urls)
                    }
                } label: {
                    Text(.localizable(.import))
                }
                Button {
                    try? archiveAllFiles()
                } label: {
                    Text(.localizable(.exportAll))
                }
            }
        }
#endif
        
#if os(macOS)
        documentGroup()

        Settings {
            SettingsView()
                .swiftyAlert()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
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
