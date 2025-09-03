//
//  ContentViewDetail.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

import ChocofordUI
import SplitView

struct ContentViewDetail: View {
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState
    
    @Binding var isSettingsPresented: Bool
    
    @StateObject private var toolState = ToolState()
    
    var body: some View {
        splitViewsContent()
            .modifier(ExcalidrawContainerToolbarContentModifier())
#if os(iOS)
            .modifier(ApplePencilToolbarModifier())
            .sheet(isPresented: $isSettingsPresented) {
                if #available(macOS 13.0, iOS 16.4, *) {
                    SettingsView()
                        .presentationContentInteraction(.scrolls)
                } else {
                    SettingsView()
                }
            }
#endif
            .environmentObject(toolState)
    }
    
    private func applyToolStateWebCoordinator() {
        // TODO: Not Good Enough
//        DispatchQueue.main.async {
//            print("=-=-=-=-=-=", fileState.excalidrawWebCoordinator, fileState.excalidrawCollaborationWebCoordinator)
//            if fileState.currentCollaborationFile != nil {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawCollaborationWebCoordinator
//            } else {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawWebCoordinator
//            }
//        }
    }
    
    @MainActor @ViewBuilder
    private func splitViewsContent() -> some View {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *), false {
            ExcalidrawSplitViewsContainer()
        } else if fileState.activeFiles.count > 0 {
            ContentDetailNavigationView(isSettingsPresented: $isSettingsPresented)
                .modifier(FileHomeItemTransitionModifier())
        }
    }
}

extension FileState.ActiveFile: FlexibleItem {
    var title: String {
        name ?? .init(localizable: .generalUntitled)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ExcalidrawSplitViewsContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState
    
    var body: some View {
//        FlexibleSplitView(items: $fileState.activeFiles) { file in
//            withAnimation {
//                fileState.activeFiles.removeAll(where: {$0?.id == file?.id})
//            }
//        } subView: { activeFile in
//            ExcalidrawContainerWrapper(activeFile: activeFile)
//                .modifier(FileHomeItemTransitionModifier())
//        }
    }
}

struct ContentDetailNavigationView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    @Binding var isSettingsPresented: Bool
    
    @StateObject private var toolState = ToolState()

    var disableInteration: Bool {
        fileState.currentActiveFile == nil
    }
    
    var background: Color {
        appPreference.excalidrawAppearance.colorScheme
        ?? appPreference.appearance.colorScheme
        ?? colorScheme == .dark
        ? Color.black
        : Color.white
    }
    
    enum HomeType {
        case home
        case fileHome
        case localFileHome
        case temporaryFileHome
        case collaborationFileHome
    }
    
    @State private var lastHomeType: HomeType = .home
    
    /// For transition
    @State private var currentGroups: [Group] = []
    @State private var currentFolders: [LocalFolder] = []
    
    @State private var isTransitioning = false
    
    var body: some View {
        ZStack {
//            background
//                .ignoresSafeArea()
//                .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)

            ExcalidrawContainerWrapper(
                activeFile: $fileState.currentActiveFile,
                interactionEnabled: !disableInteration
            )
            .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)
            
            if fileHomeItemTransitionState.canShowItemContainerView {
                switch lastHomeType {
                    case .home:
                        // Home View
                        HomeView()
                            .background {
                                if #available(macOS 14.0, iOS 17.0, *) {
                                    Rectangle()
                                        .fill(.windowBackground)
                                } else {
                                    Color.windowBackgroundColor
                                }
                            }
                            .opacity(
                                fileHomeItemTransitionState.canShowItemContainerView ||
                                fileState.currentActiveFile == nil && fileState.currentActiveGroup == nil
                                ? 1
                                : 0
                            )
                        
                    case .fileHome:
                        // File Home View
                        ZStack {
                            ForEach(Array(currentGroups.enumerated()), id: \.element) { i, group in
                                GroupFileHomeView(group: group)
                                    .opacity(
                                        fileHomeItemTransitionState.canShowItemContainerView ||
                                        fileState.currentActiveFile == nil
                                        ? 1
                                        : 0
                                    )
                                    .background {
                                        ZStack {
                                            if #available(macOS 14.0, iOS 17.0, *) {
                                                Rectangle()
                                                    .fill(.windowBackground)
                                            } else {
                                                Color.windowBackgroundColor
                                            }
                                        }
                                        .shadow(
                                            color: .gray.opacity(isTransitioning && i == currentGroups.endIndex - 1 ? 0.3 : 0.0),
                                            radius: 0,
                                            x: -1
                                        )
                                        .animation(
                                            .default,
                                            value: isTransitioning && i == currentGroups.endIndex - 1
                                        )
                                    }
                                    .transition(
                                        .move(edge: .trailing)
                                    )
                            }
                        }
                    case .localFileHome:
                        ZStack {
                            LocalFoldersProvider { _ in
                                ForEach(Array(currentFolders.enumerated()), id: \.element) { i, folder in
                                    LocalFolderFileHomeView(folder: folder)
                                        .opacity(
                                            fileHomeItemTransitionState.canShowItemContainerView ||
                                            fileState.currentActiveFile == nil
                                            ? 1
                                            : 0
                                        )
                                        .background {
                                            ZStack {
                                                if #available(macOS 14.0, iOS 17.0, *) {
                                                    Rectangle()
                                                        .fill(.windowBackground)
                                                } else {
                                                    Color.windowBackgroundColor
                                                }
                                            }
                                            .shadow(
                                                color: .gray.opacity(isTransitioning && i == currentFolders.endIndex - 1 ? 0.3 : 0.0),
                                                radius: 0,
                                                x: -1
                                            )
                                            .animation(
                                                .default,
                                                value: isTransitioning && i == currentFolders.endIndex - 1
                                            )
                                        }
                                        .transition(
                                            .move(edge: .trailing)
                                        )
                                }
                            }
                        }
                    case .temporaryFileHome:
                        TemporaryFilesHomeView()
                            .opacity(
                                fileHomeItemTransitionState.canShowItemContainerView ||
                                fileState.currentActiveFile == nil
                                ? 1
                                : 0
                            )
                    case .collaborationFileHome:
                        CollaborationHome()
                            .opacity(
                                fileHomeItemTransitionState.canShowItemContainerView ||
                                fileState.currentActiveFile == nil
                                ? 1
                                : 0
                            )
                }
            }
        }
        .onChange(of: fileState.currentActiveFile) { newValue in
            if newValue == nil {
                initCurrentGroups()
                
                updateLastHomeType()
            }
        }
        .watchImmediately(of: fileState.currentActiveGroup) { newValue in
            switch newValue {
                case .group(let newValue):
                    if currentGroups.isEmpty {
                        initCurrentGroups()
                    } else if currentGroups.contains(newValue) {
                        let index = currentGroups.firstIndex(of: newValue)!
                        withAnimation(.smooth(duration: 0.4)) {
                            currentGroups = Array(currentGroups.prefix(upTo: index + 1))
                        }
                    } else {
                        isTransitioning = true
                        DispatchQueue.main.async {
                            withAnimation(.smooth(duration: 0.4)) {
                                currentGroups.append(newValue)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isTransitioning = false
                            }
                        }
                    }
                    
                case .localFolder(let newValue):
                    if currentFolders.isEmpty {
                        initCurrentGroups()
                    } else if currentFolders.contains(newValue) {
                        let index = currentFolders.firstIndex(of: newValue)!
                        withAnimation(.smooth(duration: 0.4)) {
                            currentFolders = Array(currentFolders.prefix(upTo: index + 1))
                        }
                    } else {
                        isTransitioning = true
                        DispatchQueue.main.async {
                            withAnimation(.smooth(duration: 0.4)) {
                                currentFolders.append(newValue)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isTransitioning = false
                            }
                        }
                    }
                    
                default:
                    currentGroups.removeAll()
            }
            
            
            
            
            if fileState.currentActiveFile == nil {
                updateLastHomeType()
            }
        }
    }
    
    private func initCurrentGroups() {
        switch fileState.currentActiveGroup {
            case .group(let currentGroup):
                // file all parents
                var parents: [Group] = [currentGroup]
                var p = currentGroup
                while let parent = p.parent {
                    parents.append(parent)
                    p = parent
                }
                currentGroups = parents.reversed()
                
            case .localFolder(let folder):
                // file all parents
                var parents: [LocalFolder] = [folder]
                var p = folder
                while let parent = p.parent {
                    parents.append(parent)
                    p = parent
                }
                currentFolders = parents.reversed()
            
            default:
                break
        }
    }
    
    private func updateLastHomeType() {
        switch fileState.currentActiveGroup {
            case .group:
                lastHomeType = .fileHome
            case .localFolder:
                lastHomeType = .localFileHome
            case .temporary:
                lastHomeType = .temporaryFileHome
            case .collaboration:
                lastHomeType = .collaborationFileHome
            default:
                lastHomeType = .home
        }
    }
    
}


struct ExcalidrawContainerWrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState

    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool
    
    init(
        activeFile: Binding<FileState.ActiveFile?>,
        interactionEnabled: Bool = true
    ) {
        self._activeFile = activeFile
        self.interactionEnabled = interactionEnabled
    }
    
    var localFileBinding: Binding<ExcalidrawFile?> {
        Binding<ExcalidrawFile?> {
            switch activeFile {
                case .file(let file):
                    return try? ExcalidrawFile(from: file.objectID, context: viewContext)
                case .localFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                case .temporaryFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                default:
                    return nil
            }
        } set: { val in
            guard let val else { return }
            do {
                switch activeFile {
                    case .file(let file):
                        if file.id == val.id {
                            // Everytime load a new file will cause an actual update.
                            let oldElements = try ExcalidrawFile(
                                from: file.objectID,
                                context: viewContext
                            ).elements
                            viewContext.perform { file.visitedAt = .now }
                            if val.elements == oldElements {
                                print("[updateCurrentFile] no updates, ignored.")
                                return
                            }
                            fileState.updateFile(file, with: val)
                        }
                    case .localFile(let url):
                        guard case .localFolder(let folder) = fileState.currentActiveGroup else { return }
                        Task {
                            try folder.withSecurityScopedURL { _ in
                                do {
                                    let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                    if val.elements == oldElements {
                                        print("[updateCurrentFile] no updates, ignored.")
                                        return
                                    }
                                    try await fileState.updateLocalFile(
                                        to: url,
                                        with: val,
                                        context: viewContext
                                    )
                                } catch {
                                    alertToast(error)
                                }
                            }
                        }
                    case .temporaryFile(let url):
                        Task {
                            do {
                                let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                if val.elements == oldElements {
                                    print("[updateCurrentFile] no updates, ignored.")
                                    return
                                }
                                try await fileState.updateLocalFile(
                                    to: url,
                                    with: val,
                                    context: viewContext
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    default:
                        break
                }
            } catch { }
        }
    }
    
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = activeFile {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        ZStack {
            ExcalidrawContainerView(
                file: localFileBinding,
                interactionEnabled: interactionEnabled
            )
            .opacity(isInCollaborationSpace ? 0 : 1)
            .allowsHitTesting(!isInCollaborationSpace)

            ExcalidrawCollabContainerView()
                .opacity(isInCollaborationSpace ? 1 : 0)
                .allowsHitTesting(isInCollaborationSpace)
        }
#if os(iOS)
        .modifier(ApplePencilToolbarModifier())
        .sheet(isPresented: $isSettingsPresented) {
            if #available(macOS 13.0, iOS 16.4, *) {
                SettingsView()
                    .presentationContentInteraction(.scrolls)
            } else {
                SettingsView()
            }
        }
#endif
//        .environmentObject(toolState)
//        .overlay {
//            splitViewsContent()
//        }
        .allowsHitTesting(interactionEnabled)
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        
    } else {
        EmptyView()
    }
}

