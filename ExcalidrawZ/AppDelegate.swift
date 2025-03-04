//
//  AppDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation
import SwiftUI

extension Notification.Name {
    static let didOpenFromUrls = Notification.Name("DidOpenFromUrls")
}

#if os(macOS)
import AppKit
class AppDelegate: NSObject, NSApplicationDelegate {
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
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        print("application did open file")
        return true
    }
    
    func application(_ sender: Any, openFileWithoutUI filename: String) -> Bool {
        print(#function)
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        print(#function)
    }
}


#elseif os(iOS)
import UIKit
class AppDelegate: NSObject, UIApplicationDelegate {

}
#endif
