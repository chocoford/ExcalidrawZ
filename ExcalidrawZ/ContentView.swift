//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import CoreData
import CloudKit
import Combine
import os.log

import ChocofordUI
import ChocofordEssentials
import SwiftyAlert

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")
    
    @State private var hideContent: Bool = false
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    @StateObject private var layoutState = LayoutState()
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isFirstImporting: Bool?
    @State private var cloudContainerEventChangeListener: AnyCancellable?
    
    var body: some View {
        ZStack {
            if isFirstImporting == nil {
                Color.clear
            } else if isFirstImporting == true {
                if #available(macOS 13.0, *) {
                    welcomeView()
                } else {
                    welcomeView()
                        .frame(width: 1150, height: 580)
                }
            } else {
                if #available(macOS 14.0, iOS 17.0, *), appPreference.inspectorLayout == .sidebar {
                    content()
                        .inspector(isPresented: $layoutState.isInspectorPresented) {
                            LibraryView()
                                .inspectorColumnWidth(min: 240, ideal: 250, max: 300)
                        }
                } else {
                    content()
                    if appPreference.inspectorLayout == .floatingBar {
                        HStack {
                            Spacer()
                            if layoutState.isInspectorPresented {
                                LibraryView()
                                    .frame(minWidth: 240, idealWidth: 250, maxWidth: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .background {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.regularMaterial)
                                            .shadow(radius: 4)
                                    }
                                    .transition(.move(edge: .trailing))
                            }
                        }
                        .animation(.easeOut, value: layoutState.isInspectorPresented)
                        .padding(.top, 10)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationTitle("")
        .modifier(PrintModifier())
        .modifier(WhatsNewSheetViewModifier())
#if os(iOS)
        .modifier(ApplePencilToolbarModifier())
#endif
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .environmentObject(layoutState)
        .swiftyAlert(logs: true)
        .bindWindow($window)
        .containerSizeClassInjection()
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleImport)) { notification in
            guard let urls = notification.object as? [URL] else { return }
            if window?.isKeyWindow == true {
                Task.detached {
                    do {
                        try await fileState.importFiles(urls)
                    } catch {
                        print(error)
                        await alertToast(error)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenFromUrls)) { notification in
            if let urls = notification.object as? [URL] {
                fileState.temporaryFiles.append(contentsOf: urls)
                fileState.temporaryFiles = Array(Set(fileState.temporaryFiles))
                if !fileState.isTemporaryGroupSelected || fileState.currentTemporaryFile == nil {
                    fileState.isTemporaryGroupSelected = true
                    fileState.currentTemporaryFile = fileState.temporaryFiles.first
                }
            }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            onOpenURL(url)
        }
        // Check if it is first launch by checking the files count.
        .task {
            do {
                let isEmpty = try viewContext.fetch(NSFetchRequest<File>(entityName: "File")).isEmpty
                isFirstImporting = isEmpty
                if isFirstImporting == true, try await CKContainer.default().accountStatus() != .available {
                    isFirstImporting = false
                    return
                } else if !isEmpty {
                    try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                }
            } catch {
                alertToast(error)
            }
            
            self.cloudContainerEventChangeListener?.cancel()
            self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            ).sink { notification in
                if let userInfo = notification.userInfo {
                    if let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event {
                        // On macOS, event.type will be `setup` only when first launched.
                        // On iOS, event.type will be `setup` every time it has been launched.
                        print("NSPersistentCloudKitContainer.eventChangedNotification: \(event.type), succeeded: \(event.succeeded)")
                        if event.type == .import, event.succeeded, isFirstImporting == true {
                            isFirstImporting = false
                            Task { @MainActor in
                                do {
                                    try? await Task.sleep(nanoseconds: UInt64(2 * 1e+9))
                                    try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: viewContext)
                                } catch {
                                    alertToast(error)
                                }
                            }
                            self.cloudContainerEventChangeListener?.cancel()
                        }
                    }
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 13.0, *), appPreference.sidebarLayout == .sidebar {
            ContentViewModern()
        } else {
            ContentViewLagacy()
        }
    }
    
    @MainActor @ViewBuilder
    private func welcomeView() -> some View {
        ProgressView {
            VStack {
                if isFirstImporting == true {
                    Text(.localizable(.welcomeTitle)).font(.title)
                    Text(.localizable(.welcomeDescription))
                } else {
                    Text(.localizable(.welcomeSyncing))
                }
            }
        }
        .padding(40)
    }
    
    private func onOpenURL(_ url: URL) {
        // check if it is already in LocalFolder
        let context = viewContext
        var canAddToTemp = true
        do {
            try context.performAndWait {
                let folderFetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                folderFetchRequest.predicate = NSPredicate(format: "filePath == %@", url.deletingLastPathComponent().filePath)
                guard let folder = try context.fetch(folderFetchRequest).first else {
                    return
                }
                canAddToTemp = false
                Task {
                    await MainActor.run {
                        fileState.currentLocalFolder = folder
                        fileState.expandToGroup(folder.objectID)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.1))
                    await MainActor.run {
                        fileState.currentLocalFile = url
                    }
                }
            }
        } catch {
            alertToast(error)
        }
        
        guard canAddToTemp else { return }
        
        // logger.debug("on open url: \(url, privacy: .public)")
        if !fileState.temporaryFiles.contains(where: {$0 == url}) {
            fileState.temporaryFiles.append(url)
        }
        if !fileState.isTemporaryGroupSelected || fileState.currentTemporaryFile == nil {
            fileState.isTemporaryGroupSelected = true
            fileState.currentTemporaryFile = fileState.temporaryFiles.first
        }
        // save a checkpoint immediately.
        Task.detached {
            do {
                try await context.perform {
                    let newCheckpoint = LocalFileCheckpoint(context: context)
                    newCheckpoint.url = url
                    newCheckpoint.updatedAt = .now
                    newCheckpoint.content = try Data(contentsOf: url)
                    
                    context.insert(newCheckpoint)
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct PrintModifier: ViewModifier {
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var exportState: ExportState

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isPreparingForPrint = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(isPreparingForPrint)) {
                ProgressView {
                    Text(.localizable(.generalLoading))
                }
                .padding(.horizontal, 40)
            }
            .bindWindow($window)
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .togglePrintModalSheet)) { _ in
                if window?.isKeyWindow == true {
                    isPreparingForPrint = true
                    Task.detached(priority: .background) {
                        do {
                            let imageData = try await exportState.exportCurrentFileToImage(
                                type: .png,
                                embedScene: false,
                                withBackground: true
                            ).data
                            await MainActor.run {
                                if let image = NSImage(dataIgnoringOrientation: imageData) {
                                    exportPDF(image: image)
                                }
                            }
                        } catch {
                            await alertToast(error)
                        }
                        await MainActor.run {
                            isPreparingForPrint = false
                        }
                    }
                }
            }
#endif
    }
}

@available(macOS 13.0, *)
struct ContentViewModern: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
        
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isSettingsPresented = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if #available(macOS 14.0, iOS 17.0, *) {
#if os(macOS)
                SidebarView()
                    .toolbar(content: sidebarToolbar)
                    .toolbar(removing: .sidebarToggle)
#elseif os(iOS)
                if horizontalSizeClass == .compact {
                    SidebarView()
                        .toolbar(content: sidebarToolbar)
                        .toolbar(removing: .sidebarToggle)
                } else {
                    SidebarView()
                        .toolbar(content: sidebarToolbar)
                }
#endif
            } else {
                SidebarView()
                    .toolbar(content: sidebarToolbar)
            }
        } detail: {
            ExcalidrawContainerView()
                .modifier(ExcalidrawContainerToolbarContentModifier())
        }
#if os(macOS)
        .removeSettingsSidebarToggle()
#elseif os(iOS)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
#endif
        .onChange(of: columnVisibility) { newValue in
            layoutState.isSidebarPresented = newValue != .detailOnly
        }
    }
    
    @ToolbarContentBuilder
    private func sidebarToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // create
            NewFileButton()
        }
        
#if os(macOS)
        // in macOS 14.*, the horizontalSizeClass is not `.regular`
        // if horizontalSizeClass == .regular {
            ToolbarItemGroup(placement: .destructiveAction) {
                SidebarToggle(columnVisibility: $columnVisibility)
            }
        // }
#elseif os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                isSettingsPresented.toggle()
            } label: {
                Label(.localizable(.settingsName), systemSymbol: .gear)
            }
        }
#endif
//        ToolbarItemGroup(placement: .confirmationAction) {
//            Color.blue.frame(width: 10, height: 10)
//        }
//        ToolbarItemGroup(placement: .status) {
//            Color.yellow.frame(width: 10, height: 10)
//        }
//        ToolbarItemGroup(placement: .principal) {
//            Color.green.frame(width: 10, height: 10)
//        }
//
//        ToolbarItemGroup(placement: .cancellationAction) {
//            Color.red.frame(width: 10, height: 10)
//        }
//
#if os(macOS)
        /// It is neccessary for macOS to `space-between` the new button and sidebar toggle.
        ToolbarItemGroup(placement: .secondaryAction) {
            Color.clear
        }
#endif
    }
}

struct ContentViewLagacy: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var layoutState: LayoutState
    
    
    var body: some View {
        ZStack {
            ExcalidrawContainerView()
                .modifier(ExcalidrawContainerToolbarContentModifier())
                .layoutPriority(1)
            
            HStack {
                if layoutState.isSidebarPresented {
                    SidebarView()
                        .frame(width: 374)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .shadow(radius: 4)
                        }
                        .transition(.move(edge: .leading))
                }
                Spacer()
            }
            .animation(.easeOut, value: layoutState.isSidebarPresented)
            .animation(.easeOut, value: layoutState.isInspectorPresented)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 40)
        }
    }
}

#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
#endif
