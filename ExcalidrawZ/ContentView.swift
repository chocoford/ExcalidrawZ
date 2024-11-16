//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials
import SwiftyAlert

struct ContentView: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    
    @State private var hideContent: Bool = false
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    
    @State private var sharedFile: File?
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isMigrateSheetPresented = false
    
    @State private var isInspectorPresented: Bool = false
    @State private var isSidebarPresented: Bool = true
    @State private var isExcalidrawToolbarDense: Bool = false

    var body: some View {
        ZStack {
            if #available(macOS 14.0, iOS 17.0, *), appPreference.inspectorLayout == .sidebar {
                content()
                    .inspector(isPresented: $isInspectorPresented) {
                        LibraryView(isPresented: $isInspectorPresented)
                            .inspectorColumnWidth(min: 240, ideal: 250, max: 300)
                    }
            } else {
                content()
                if appPreference.inspectorLayout == .floatingBar {
                    HStack {
                        Spacer()
                        if isInspectorPresented {
                            LibraryView(isPresented: $isInspectorPresented)
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
                    .animation(.easeOut, value: isInspectorPresented)
                    .padding(.top, 10)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar { toolbarContent() }
        .navigationTitle("")
        .sheet(item: $sharedFile) {
            if #available(macOS 13.0, iOS 16.0, *) {
                ShareView(sharedFile: $0)
                    .swiftyAlert()
            } else {
                ShareViewLagacy(sharedFile: $0)
                    .swiftyAlert()
            }
        }
        .modifier(MigrateToNewVersionSheetViewModifier(isPresented: $isMigrateSheetPresented))
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .swiftyAlert()
        .bindWindow($window)
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
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 13.0, *), appPreference.sidebarLayout == .sidebar {
            ContentViewModern(isSidebarPresented: $isSidebarPresented)
        } else {
            ContentViewLagacy(
                isSidebarPresented: $isSidebarPresented,
                isInspectorPresented: $isInspectorPresented
            )
        }
    }
}

@available(macOS 13.0, *)
struct ContentViewModern: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var appPreference: AppPreference
    
    @Binding var isSidebarPresented: Bool
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if #available(macOS 14.0, iOS 17.0, *) {
                SidebarView()
                    .toolbar(content: sidebarToolbar)
                    .toolbar(removing: .sidebarToggle)
            } else {
                SidebarView()
                    .toolbar(content: sidebarToolbar)
            }
        } detail: {
            ExcalidrawContainerView()
        }
#if os(macOS)
        .removeSettingsSidebarToggle()
#endif
        .onChange(of: columnVisibility) { newValue in
            isSidebarPresented = newValue != .detailOnly
        }
    }
    
    @ToolbarContentBuilder
    private func sidebarToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // create
            Button {
                do {
                    try fileState.createNewFile()
                } catch {
                    alertToast(error)
                }
            } label: {
                Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
            }
            .help(.localizable(.createNewFile))
            .disabled(fileState.currentGroup?.groupType == .trash)
        }
        
        ToolbarItemGroup(placement: .destructiveAction) {
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
        ToolbarItemGroup(placement: .secondaryAction) {
            Color.clear
        }
    }
}

struct ContentViewLagacy: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    @Binding var isSidebarPresented: Bool
    @Binding var isInspectorPresented: Bool
    
    var body: some View {
        ZStack {
            ExcalidrawContainerView()
                .layoutPriority(1)
            
            HStack {
                if isSidebarPresented {
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
            .animation(.easeOut, value: isSidebarPresented)
            .animation(.easeOut, value: isInspectorPresented)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Toolbar Content
extension ContentView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
#if os(iOS)
        toolbarContent_iOS()
#else
        toolbarContent_macOS()
#endif
    }
    
//#if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        toolbarContent_macOS()
    }
//#else
    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
            if #available(macOS 13.0, iOS 16.0, *) {
                ExcalidrawToolbar(
                    isInspectorPresented: appPreference.inspectorLayout == .sidebar ? $isInspectorPresented : .constant(false),
                    isSidebarPresented: appPreference.sidebarLayout == .sidebar ? $isSidebarPresented : .constant(false),
                    isDense: $isExcalidrawToolbarDense
                )
                .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar(
                    isInspectorPresented: .constant(false),
                    isSidebarPresented: .constant(false),
                    isDense: $isExcalidrawToolbarDense
                )
                .offset(y: isExcalidrawToolbarDense ? 0 : 6)
            }
        }
        
        ToolbarItemGroup(placement: .navigation) {
            if #available(macOS 13.0, iOS 16.0, *), appPreference.sidebarLayout == .sidebar { } else {
                Button {
                    isSidebarPresented.toggle()
                } label: {
                    Label("Sidebar", systemSymbol: .sidebarLeft)
                }
            }
            
            if let file = fileState.currentFile {
                VStack(alignment: .leading) {
                    Text(file.name ?? "")
                        .font(.headline)
                    Text(file.createdAt?.formatted() ?? "Not modified")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            
            if #available(macOS 13.0, iOS 16.0, *) { } else {
                // create
                Button {
                    do {
                        try fileState.createNewFile()
                    } catch {
                        alertToast(error)
                    }
                } label: {
                    Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
                }
                .help(.localizable(.createNewFile))
                .disabled(fileState.currentGroup?.groupType == .trash)
            }
        }
        
        ToolbarItemGroup(placement: .cancellationAction) {
            SettingsButton(useDefaultLabel: true) {
                
            } label: {
                Label("Settings", systemSymbol: .gear)
                    .labelStyle(.iconOnly)
            }
        }
        
        
        ToolbarItemGroup(placement: .automatic) {
//            Spacer()
            if let currentFile = fileState.currentFile {
                Popover {
                    FileCheckpointListView(file: currentFile)
                } label: {
                    Label(.localizable(.checkpoints), systemSymbol: .clockArrowCirclepath)
                }
                .disabled(fileState.currentGroup?.groupType == .trash)
                .help(.localizable(.checkpoints))
            }

            Button {
                self.sharedFile = fileState.currentFile
            } label: {
                Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
            }
            .help(.localizable(.export))
            .disabled(fileState.currentGroup?.groupType == .trash)


            if #available(macOS 13.0, iOS 16.0, *), appPreference.inspectorLayout == .sidebar { } else {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Library", systemSymbol: .sidebarRight)
                }
            }
        }
    }
//#endif
}

#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
#endif
