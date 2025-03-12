//
//  AppDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation
import SwiftUI
import os.log

extension Notification.Name {
    static let didOpenFromUrls = Notification.Name("DidOpenFromUrls")
}

#if os(macOS)
import AppKit
class AppDelegate: NSObject, NSApplicationDelegate {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
    
    var openedURLs: [URL] = []
    var didLaunched = false
    
    func applicationWillTerminate(_ notification: Notification) {
        PersistenceController.shared.save()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        DispatchQueue.main.async {
            do {
                try backupFiles(context: PersistenceController.shared.container.viewContext)
            } catch {
                print(error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if NSApp.windows.filter({$0.canBecomeMain}).isEmpty {
                    NSApp.terminate(nil)
                }
            }
        }
        return false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info(#function)
        if !openedURLs.isEmpty {
            NotificationCenter.default.post(name: .didOpenFromUrls, object: openedURLs)
        }
        didLaunched = true
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        logger.info("application did open file")
        return true
    }
    
    func application(_ sender: Any, openFileWithoutUI filename: String) -> Bool {
        print(#function)
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        logger.info(#function)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("\(#function), urls: \(urls, privacy: .public)")
        openedURLs = urls
        if didLaunched, !urls.isEmpty {
            NotificationCenter.default.post(name: .didOpenFromUrls, object: urls)
        }
    }
}


#elseif os(iOS)
import UIKit
class AppDelegate: NSObject, UIApplicationDelegate {

}
#endif
