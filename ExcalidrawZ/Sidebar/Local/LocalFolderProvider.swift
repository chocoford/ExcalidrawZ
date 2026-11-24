//
//  LocalFolderProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/22/25.
//

import SwiftUI
import SwiftyAlert
import CoreData

import ChocofordUI

struct LocalFoldersProvider<Content: View>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @Environment(\.scenePhase) private var scenePhase

    @Environment(FileState.self) private var fileState

    var content: (FetchedResults<LocalFolder>) -> Content
    init(
        @ViewBuilder content: @escaping (FetchedResults<LocalFolder>) -> Content
    ) {
        self.content = content
    }

    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.rank, order: .forward),
            SortDescriptor(\.importedAt, order: .forward),
        ],
        predicate: NSPredicate(format: "parent == nil")
    )
    var folders: FetchedResults<LocalFolder>

    @Environment(LocalFolderState.self) private var localFolderState

#if canImport(AppKit)
    typealias PlatformWindow = NSWindow
#elseif canImport(UIKit)
    typealias PlatformWindow = UIWindow
#endif

    @State private var window: PlatformWindow?
    @State private var folderUrlBeforeResignKey: URL?

    
    var body: some View {
        content(folders)
            .bindWindow($window)
    #if os(macOS)
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            ) { notification in
                if let window = notification.object as? NSWindow,
                   window == self.window {
                    self.refreshFoldersContent()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                if let window = notification.object as? NSWindow,
                   window == self.window {
                    if case .localFolder(let localFolder) = fileState.currentActiveGroup {
                        self.folderUrlBeforeResignKey = localFolder.url
                    }
                }
            }
#elseif os(iOS)
            .watch(value: scenePhase) { newValue in
                if newValue == .active {
                    self.refreshFoldersContent()
                }
            }
#endif
            .onReceive(NotificationCenter.default.publisher(for: .localFolderResolvedLocationDidChange)) { notification in
                guard let previous = folderUrlBeforeResignKey,
                      let oldURL = notification.userInfo?[LocalFolderLocationChangeUserInfoKey.oldURL] as? URL,
                      let newURL = notification.userInfo?[LocalFolderLocationChangeUserInfoKey.newURL] as? URL else { return }
                folderUrlBeforeResignKey = previous.rebased(from: oldURL, to: newURL) ?? previous
            }
    }

    private func refreshFoldersContent() {
        Task {
            await LinkedFolderIndexState.refreshRootLocations()
            await LinkedFolderIndexState.configureFromPersistence()
            await LinkedFolderIndex.shared.reconcile()
            do { try redirectToCurrentFolder() } catch { alertToast(error) }
            folderUrlBeforeResignKey = nil
        }
    }

    private func redirectToCurrentFolder() throws {
        guard fileState.currentActiveGroup == nil, let folderUrlBeforeResignKey else { return }
        let context = viewContext
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        fetchRequest.predicate = NSPredicate(format: "filePath == %@", folderUrlBeforeResignKey.filePath)
        fetchRequest.fetchLimit = 1

        if let folder = try context.fetch(fetchRequest).first {
            fileState.currentActiveGroup = .localFolder(folder)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let iCloudFileStatusDidChange = Notification.Name("iCloudFileStatusDidChange")
    static let iCloudFileDidStartDownloading = Notification.Name("iCloudFileDidStartDownloading")
    static let iCloudFileDidFinishDownloading = Notification.Name("iCloudFileDidFinishDownloading")
}
