//
//  ExcalidrawZApp.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
#if os(macOS) && !APP_STORE
import Sparkle
#endif

@main
@MainActor
struct ExcalidrawZApp: App {
    let store = AppStore(state: AppState(),
                         reducer: appReducer,
                         environment: AppEnvironment())
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
    
    @State private var timer = Timer.publish(every: 30, on: .main, in: .default).autoconnect()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .onReceive(timer) { _ in
                    store.send(.saveCoreData, log: false)
                }
        }
#if os(macOS) && !APP_STORE
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
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
                    let panel = ExcalidrawOpenPanel.exportPanel
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            let filemanager = FileManager.default
                            do {
                                let allFiles = try PersistenceController.shared.listAllFiles()
                                let exportURL = url.appendingPathComponent("ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))", conformingTo: .directory)
                                try filemanager.createDirectory(at: exportURL, withIntermediateDirectories: false)
                                for files in allFiles {
                                    let dir = exportURL.appendingPathComponent(files.key, conformingTo: .directory)
                                    try filemanager.createDirectory(at: dir, withIntermediateDirectories: false)
                                    for file in files.value {
                                        let filePath = dir.appendingPathComponent(file.name ?? "untitled", conformingTo: .fileURL).appendingPathExtension("excalidraw")
                                        let path = filePath.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? ""//.path(percentEncoded: false) 
                                        print(path)
                                        if !filemanager.createFile(atPath: path, contents: file.content) {
                                            print("export file \(path) failed")
                                        }
                                    }
                                }
                            } catch {
                                store.send(.setError(.unexpected(error)))
                            }
                        } else {
                            store.send(.setError(.fileError(.invalidURL)))
                        }
                    }
                } label: {
                    Text("Export All")
                }
            }
        }
#endif
        .onChange(of: scenePhase) { _ in
            //            store.send(.saveCoreData)
        }
    }
}

//extension Scene {
//    @SceneBuilder func defaultSizeCompatible(width: CGFloat, height: CGFloat) -> some Scene {
//        if #available(macOS 13.0, *) {
//            defaultSize(width: width, height: height)
//        } else {
//            // Fallback on earlier versions
//        }
////        if #available(macOS 13.0, *) {
////            defaultSize(width: width, height: height)
////        } else {
////            self
////        }
//    }
//}
