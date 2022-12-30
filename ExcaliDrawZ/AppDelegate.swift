//
//  AppDelegate.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation


#if os(macOS)
import AppKit
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

#elseif os(iOS)
import UIKit
class AppDelegate: NSObject, UIApplicationDelegate {

}
#endif
