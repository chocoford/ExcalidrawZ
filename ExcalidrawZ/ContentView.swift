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

import ChocofordUI
import ChocofordEssentials
import SwiftyAlert

struct ContentView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    
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
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .environmentObject(layoutState)
        .swiftyAlert()
        .bindWindow($window)
        .modifier(WhatsNewSheetViewModifier())
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
        // Check if it is first launch by checking the files count.
        .task {
            do {
                let isEmpty = try managedObjectContext.fetch(NSFetchRequest<File>(entityName: "File")).isEmpty
                isFirstImporting = isEmpty
                if isFirstImporting == true, try await CKContainer.default().accountStatus() != .available {
                    isFirstImporting = false
                    return
                } else if !isEmpty {
                    try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: managedObjectContext)
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
                                    try await fileState.mergeDefaultGroupAndTrashIfNeeded(context: managedObjectContext)
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
                    Text("Welcome to ExcalidrawZ").font(.title)
                    Text("We are synchronizing your data, please wait...")
                } else {
                    Text("Syncing data...")
                }
            }
        }
        .padding(40)
    }
}

@available(macOS 13.0, *)
struct ContentViewModern: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
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
            Button {
                do {
                    try fileState.createNewFile(context: managedObjectContext)
                } catch {
                    alertToast(error)
                }
            } label: {
                Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
            }
            .help(.localizable(.createNewFile))
            .disabled(fileState.currentGroup?.groupType == .trash)
        }
        
#if os(macOS)
        // in macOS 14.*, the horizontalSizeClass is not `.regular`
        // if horizontalSizeClass == .regular {
            ToolbarItemGroup(placement: .destructiveAction) {
                sidebarToggle()
            }
        // }
#elseif os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                isSettingsPresented.toggle()
            } label: {
                Label("Settings", systemSymbol: .gear)
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
    
    @MainActor @ViewBuilder
    private func sidebarToggle() -> some View {
        HStack(spacing: 0) {
            Button {
                withAnimation {
                    if columnVisibility == .detailOnly {
                        columnVisibility = .all
                    } else {
                        columnVisibility = .detailOnly
                    }
                }
            } label: {
                Image(systemSymbol: .sidebarLeading)
            }
            
            Menu {
                Button {
                    withAnimation { columnVisibility = .all }
                    appPreference.sidebarMode = .all
                } label: {
                    if appPreference.sidebarMode == .all && columnVisibility != .detailOnly {
                        Image(systemSymbol: .checkmark)
                    }
                    Text(.localizable(.sidebarShowAll))
                }
                Button {
                    withAnimation { columnVisibility = .all }
                    appPreference.sidebarMode = .filesOnly
                } label: {
                    if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
                        Image(systemSymbol: .checkmark)
                    }
                    Text(.localizable(.sidebarShowFilesOnly))
                }
            } label: {
            }
            .buttonStyle(.borderless)
        }
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
                        .frame(width: 340)
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
