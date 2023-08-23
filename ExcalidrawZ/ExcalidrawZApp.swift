//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import ComposableArchitecture
#if os(macOS) && !APP_STORE
import Sparkle
#endif

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
    
    @StateObject private var appSettings = AppSettingsStore()
    @StateObject private var updateChecker = UpdateChecker()

    @State private var timer = Timer.publish(every: 30, on: .main, in: .default).autoconnect()
    let store = Store(initialState: AppViewStore.State()) {
        AppViewStore()._printChanges()
    }
    var body: some Scene {
        WindowGroup {
            ContentView(store: self.store)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .preferredColorScheme(appSettings.appearance.colorScheme)
            .environmentObject(appSettings)
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
                            store.send(.importFile(url))
                        } else {
                            store.send(.setError(.fileError(.invalidURL)))
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
        .onChange(of: scenePhase) { _ in
            //            store.send(.saveCoreData)
        }
        
        
        Settings {
            SettingsView()
                .environmentObject(appSettings)
                .environmentObject(updateChecker)
                .preferredColorScheme(appSettings.appearance.colorScheme)

        }
    }
}
