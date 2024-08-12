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
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    
    @State private var sharedFile: File?
    
    @State private var window: NSWindow?
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .toolbar(content: navigationToolbar)
        } detail: {
            ExcalidrawContainerView()
                .navigationTitle("")
        }
//        .toolbar(removing: .sidebarToggle) <-- not working
        .sheet(item: $sharedFile) {
            ShareView(sharedFile: $0)
                .swiftyAlert()
        }
        .toolbar { toolbarContent() }
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .swiftyAlert()
        .bindWindow($window)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleImport)) { notification in
            guard let url = notification.object as? URL else { return }
            if window?.isKeyWindow == true {
                do {
                    try fileState.importFile(url)
                } catch {
                    alertToast(error)
                }
            }
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
    
#if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        
    }
#else
    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
            ExcalidrawToolbar()
        }
        
        ToolbarItemGroup(placement: .navigation) {
            if let file = fileState.currentFile {
                VStack(alignment: .leading) {
                    Text(file.name ?? "Untitled")
                        .font(.headline)
                    Text(file.createdAt?.formatted() ?? "Not modified")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            
            if let currentFile = fileState.currentFile {
                Popover {
                    FileCheckpointListView(file: currentFile)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .disabled(fileState.currentGroup?.groupType == .trash)
            }

            Button {
                self.sharedFile = fileState.currentFile
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share")
            .disabled(fileState.currentGroup?.groupType == .trash)

        }
    }
#endif
    
    @ToolbarContentBuilder
    private func navigationToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // create
            Button {
                do {
                    try fileState.createNewFile()
                } catch {
                    alertToast(error)
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New draw")
            .disabled(fileState.currentGroup?.groupType == .trash)
        }
        
        
        ToolbarItemGroup(placement: .destructiveAction) {
            HStack(spacing: 0) {
                if #available(macOS 15.0, *) {
                    // Do not show the toggle..
                    Menu {
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .all
                        } label: {
                            if appPreference.sidebarMode == .all && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show folders and files")
                        }
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .filesOnly
                        } label: {
                            if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show files only")
                        }
                    } label: { }
                        .buttonStyle(.borderless)
                        .offset(x: -6)
                } else {
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
                            Text("Show folders and files")
                        }
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .filesOnly
                        } label: {
                            if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show files only")
                        }
                    } label: {
                    }
                    .buttonStyle(.borderless)
                }
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


#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
#endif
