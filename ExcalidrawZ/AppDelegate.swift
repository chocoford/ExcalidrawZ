//
//  AppDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation
import SwiftUI
import os.log
import CoreSpotlight

extension Notification.Name {
    static let didOpenFromUrls = Notification.Name("DidOpenFromUrls")
}

#if os(macOS)
import AppKit
class AppDelegate: NSObject, NSApplicationDelegate {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
    
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if NSApp.windows.filter({$0.canBecomeMain}).isEmpty {
                    NSApp.terminate(nil)
                }
            }
        }
        return false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // disable auto capitalization
        UserDefaults.standard.set(false, forKey: "NSAutomaticCapitalizationEnabled")
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
    }
    
    // Continuous Activity
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        return handleUserActivity(userActivity)
    }
}


#elseif os(iOS)
import UIKit
class AppDelegate: NSObject, UIApplicationDelegate {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return handleUserActivity(userActivity)
    }
}
#endif

extension AppDelegate {
//#if canImport(AppKit)
//    typealias PlatformUserActivityRestoring = NSUserActivityRestoring
//#elseif canImport(UIKit)
//    typealias PlatformUserActivityRestoring = UIUserActivityRestoring
//#endif
    func handleUserActivity(
        _ userActivity: NSUserActivity//,
        // restorationHandler: @escaping ([any PlatformUserActivityRestoring]?) -> Void
    ) -> Bool {
        logger.info("[AppDelegate] application received activity: \(userActivity.title ?? "")")
        if userActivity.activityType == CSSearchableItemActionType {
            NotificationCenter.default.post(name: .onContinueUserSearchableItemAction, object: userActivity)
            return true
        }
        if userActivity.activityType == CSQueryContinuationActionType {
            NotificationCenter.default.post(name: .onContinueUserQueryContinuationAction, object: userActivity)
            return true
        }
        
        return false
    }
}
