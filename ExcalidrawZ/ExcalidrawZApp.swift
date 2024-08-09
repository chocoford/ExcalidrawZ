//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI

import SwiftyAlert
#if os(macOS) && !APP_STORE
import Sparkle
#endif

extension Notification.Name {
    static let shouldHandleImport = Notification.Name("ShouldHandleImport")
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
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
#endif
    }
    
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var appPrefernece = AppPreference()
    @StateObject private var updateChecker = UpdateChecker()

    @State private var timer = Timer.publish(every: 30, on: .main, in: .default).autoconnect()
    
    var body: some Scene {
        // Can not use Document group - we should save chekpoints
        WindowGroup {
            RootView()
                .swiftyAlert()
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .environmentObject(appPrefernece)
                .onAppear {
                    updateChecker.assignUpdater(updater: updaterController.updater)
                }
        }
#if os(macOS) && !APP_STORE
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(checkForUpdatesViewModel: updateChecker)
            }
        }
#endif
#if os(macOS)
//        .defaultSizeCompatible(width: 900, height: 500)
        .commands {
            CommandGroup(after: .importExport) {
                Button {
                    let panel = ExcalidrawOpenPanel.importPanel
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            NotificationCenter.default.post(name: .shouldHandleImport, object: url)
                        }
                    }
                } label: {
                    Text("Import")
                }
                Button {
                    try? archiveAllFiles()
                } label: {
                    Text("Export All")
                }
            }
        }
#endif
        
        Settings {
            SettingsView()
                .environmentObject(appPrefernece)
                .environmentObject(updateChecker)
                .preferredColorScheme(appPrefernece.appearance.colorScheme)
        }
    }
}
