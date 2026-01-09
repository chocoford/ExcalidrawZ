//
//  LocalFolderProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/22/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFoldersProvider<Content: View>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject private var fileState: FileState

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

    @EnvironmentObject private var localFolderState: LocalFolderState

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
                    do {
                        try self.refreshFoldersContent()
                        try redirectToCurrentFolder()
                    } catch {
                        alertToast(error)
                    }
                    folderUrlBeforeResignKey = nil
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
            .onChange(of: scenePhase) { newValue in
                if newValue == .active {
                    do {
                        try self.refreshFoldersContent()
                        try redirectToCurrentFolder()
                    } catch {
                        alertToast(error)
                    }
                }
            }
#endif
    }

    @MainActor
    private func refreshFoldersContent() throws {
        for i in 0..<folders.count {
            try folders[i].refreshChildren(context: viewContext)
        }
    }

    private func redirectToCurrentFolder() throws {
        guard fileState.currentActiveGroup == nil, let folderUrlBeforeResignKey else { return }
        let context = viewContext
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        let allFolders = try context.fetch(fetchRequest)

        if let folder = allFolders.first(where: {$0.url == folderUrlBeforeResignKey}) {
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
