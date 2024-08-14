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
    
    @State private var showMigrateSheet = false
    
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
            .sheet(isPresented: $showMigrateSheet) {
                MigrateToNewVersionSheetView()
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
            .onAppear {
                showMigrateSheet = !UserDefaults.standard.bool(forKey: "PreventShowMigrationSheet")
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
    

}


struct MigrateToNewVersionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @State private var window: NSWindow?
    
    @AppStorage("PreventShowMigrationSheet") var notShowAgain = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Migrate to new version")
                .font(.largeTitle)
            
            Text("ExcalidrawZ has reached a new milestone—the official release of version 1.0. The new version has changed the application ID, so you will need to manually download it and migrate your existing files.")
            
            GeometryReader { geometry in
                let spacing: CGFloat = 10
                HStack(spacing: spacing) {
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowUp)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text("Archive all files")
                                .font(.headline)
                            Text("Export all files and import them to the new version of ExcalidrawZ.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        AsyncButton { @MainActor in
                            try archiveAllFiles()
                        } label: {
                            Text("Archive")
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
                    .background {
                        if #available(macOS 14.0, *) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                                .stroke(.separator, lineWidth: 0.5)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.separator, lineWidth: 0.5)
                            }
                        }
                    }
                    
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowDown)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text("Download the new ExcalidrawZ")
                                .font(.headline)
                            
                            Text("Two versions of ExcalidrawZ are available: the App Store version and the non-App Store version.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        HStack {
                            Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ?tab=readme-ov-file")!) {
                                Text("Non-AppStore")
                            }
                            Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ?tab=readme-ov-file")!) {
                                Text("AppStore")
                            }
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
                    .background {
                        ZStack {
                            if #available(macOS 14.0, *) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                    .stroke(.separator, lineWidth: 0.5)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.thinMaterial)
                                    
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.separator, lineWidth: 0.5)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Text("You can still continue to use the current app, and your data remains safe, but future updates will not be pushed here.")
                .padding(.horizontal, 40)
              
            HStack {
                Toggle(isOn: $notShowAgain) {
                    Text("Don't show again")
                }
                .opacity(0)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                }
                .controlSize(.large)
                .buttonStyle(.borderless)
                Spacer()
                Toggle(isOn: $notShowAgain) {
                    Text("Don't show again")
                }
            }
            .padding(.horizontal, 20)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: 600, height: 450)
        .modifier(MigrateToNewVersionSheetBackgroundModifier())
        .bindWindow($window)
        .onAppear {
            window?.backgroundColor = .clear
        }
    }
}

struct MigrateToNewVersionSheetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .background(Color.accentColor.gradient)
                .preferredColorScheme(.dark)
        } else {
            content
                .background(Color.accentColor)
                .preferredColorScheme(.dark)
        }
    }
}

#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}

#Preview {
    MigrateToNewVersionSheetView()
}
#endif
