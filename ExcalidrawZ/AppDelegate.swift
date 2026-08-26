//
//  AppDelegate.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation
import SwiftUI
import Logging
import CoreSpotlight
import MSAL

extension Notification.Name {
    static let didOpenFromUrls = Notification.Name("DidOpenFromUrls")
}

#if os(macOS)
import AppKit

@MainActor
final class ApplicationTerminationCanvasFlushCoordinator {
    static let shared = ApplicationTerminationCanvasFlushCoordinator()

    private weak var fileState: FileState?

    private init() {}

    func register(fileState: FileState) {
        self.fileState = fileState
    }

    func flushPendingCanvasSnapshot() async {
        await fileState?.flushPendingCanvasSnapshotBeforeTermination()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let logger = Logger(label: "AppDelegate")
    private var isHandlingApplicationTermination = false
    
    func applicationWillTerminate(_ notification: Notification) {
        PersistenceController.shared.save()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isHandlingApplicationTermination else {
            return .terminateCancel
        }

        isHandlingApplicationTermination = true
        showSavingPanel()
        Task { @MainActor in
            defer {
                isHandlingApplicationTermination = false
            }
            await prepareForApplicationTermination()
            closeSavingPanel()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Saving panel shown while flushing state at quit
    private var savingPanel: NSWindow?

    private func showSavingPanel() {
        guard savingPanel == nil else { return }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 96),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 96))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Saving changes…")
        label.font = .systemFont(ofSize: 13, weight: .medium)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        panel.contentView = effect
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        savingPanel = panel
    }

    private func closeSavingPanel() {
        savingPanel?.orderOut(nil)
        savingPanel = nil
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    private func prepareForApplicationTermination() async {
        await ScreenAnnotationSaveTaskManager.shared.waitUntilIdle()
        await OffscreenExcalidrawEditor.waitForPendingOperations()
        await ApplicationTerminationCanvasFlushCoordinator.shared.flushPendingCanvasSnapshot()
        PersistenceController.shared.save()
        await backupFilesBeforeTermination()
    }

    @MainActor
    private func backupFilesBeforeTermination() async {
        do {
            try await backupFiles(context: PersistenceController.shared.container.viewContext)
        } catch {
            logger.error("Backup before app termination failed: \(error)")
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // disable auto capitalization
        UserDefaults.standard.set(false, forKey: "NSAutomaticCapitalizationEnabled")
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logger.info(
            "Remote notification registration succeeded tokenBytes=\(deviceToken.count)"
        )
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.warning("Remote notification registration failed: \(error)")
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        logger.info("application did open file")
        return true
    }
    
    func application(_ sender: Any, openFileWithoutUI filename: String) -> Bool {
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        logger.info(#function)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("\(#function), urls: \(urls)")
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

private extension NSApplication {
    @MainActor
    var visibleMainWindows: [NSWindow] {
        windows.filter { window in
            window.isVisible && window.canBecomeMain && !window.isMiniaturized
        }
    }
}


#elseif os(iOS)
import UIKit
class AppDelegate: NSObject, UIApplicationDelegate {
    let logger = Logger(label: "AppDelegate")

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logger.info(
            "Remote notification registration succeeded tokenBytes=\(deviceToken.count)"
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.warning("Remote notification registration failed: \(error)")
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return handleUserActivity(userActivity)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: options[.sourceApplication] as? String
        )
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
