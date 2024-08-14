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
    
    @State private var window: NSWindow?
    
    @State private var isMigrateSheetPresented = false
        
    var body: some View {
        content()
            .navigationTitle("")
            .sheet(item: $sharedFile) {
                if #available(macOS 13.0, *) {
                    ShareView(sharedFile: $0)
                        .swiftyAlert()
                } else {
                    ShareViewLagacy(sharedFile: $0)
                        .swiftyAlert()
                }
            }
            .toolbar { toolbarContent() }
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
        if #available(macOS 13.0, *) {
            ContentViewModern()
        } else {
            ContentViewLagacy()
        }
    }
}

@available(macOS 13.0, *)
struct ContentViewModern: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var appPreference: AppPreference
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if #available(macOS 14.0, *) {
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
        .removeSettingsSidebarToggle()
    }
    
    @available(macOS 13.0, *)
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
                Image(systemName: "square.and.pencil")
            }
            .help("New draw")
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
    
    var body: some View {
        HSplitView {
            SidebarView()
                .frame(maxWidth: 500)
            ExcalidrawContainerView()
                .layoutPriority(1)
        }
        .toolbar {
            sidebarToolbar()
        }
    }
    
    @ToolbarContentBuilder
    private func sidebarToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .destructiveAction) {
            if #available(macOS 13.0, *) {
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
        }
        
        
        ToolbarItemGroup(placement: .destructiveAction) {
//            Color.purple.frame(width: 10, height: 10)
//            HStack(spacing: 0) {
//                Button {
////                    withAnimation {
////                        if columnVisibility == .detailOnly {
////                            columnVisibility = .all
////                        } else {
////                            columnVisibility = .detailOnly
////                        }
////                    }
//                } label: {
//                    Image(systemSymbol: .sidebarLeading)
//                }
//                
//                Menu {
//                    Button {
////                        withAnimation { columnVisibility = .all }
////                        appPreference.sidebarMode = .all
//                    } label: {
////                        if appPreference.sidebarMode == .all && columnVisibility != .detailOnly {
////                            Image(systemSymbol: .checkmark)
////                        }
//                        Text("Show folders and files")
//                    }
//                    Button {
////                        withAnimation { columnVisibility = .all }
////                        appPreference.sidebarMode = .filesOnly
//                    } label: {
////                        if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
////                            Image(systemSymbol: .checkmark)
////                        }
//                        Text("Show files only")
//                    }
//                } label: {
//                }
//                .buttonStyle(.borderless)
//            }
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
            if #available(macOS 13.0, *) {
                ExcalidrawToolbar()
                    .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar()
            }
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
            
            if #available(macOS 13.0, *) { } else {
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
        }

        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            
            if Bundle.main.bundleIdentifier == "com.chocoford.ExcalidrawZ" || Bundle.main.bundleIdentifier == "com.chocoford.ExcalidrawZ-Debug" {
                Button {
                    isMigrateSheetPresented.toggle()
                } label: {
                    Label("Migrate to new ExcalidrawZ", systemSymbol: .sparkles)
                }
                .help("Migrate to new ExcalidrawZ")
            }
            
            if let currentFile = fileState.currentFile {
                Popover {
                    FileCheckpointListView(file: currentFile)
                } label: {
                    Label("File history", systemSymbol: .clockArrowCirclepath)
                }
                .disabled(fileState.currentGroup?.groupType == .trash)
                .help("File history")
            }

            Button {
                self.sharedFile = fileState.currentFile
            } label: {
                Label("Share", systemSymbol: .squareAndArrowUp)
            }
            .help("Share")
            .disabled(fileState.currentGroup?.groupType == .trash)

        }
    }
#endif
    

}




#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}


#endif
