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

    var disableInteration: Bool {
        !fileState.hasAnyActiveFile && !fileState.hasAnyActiveGroup ||
        fileState.currentGroup != nil && fileState.currentFile == nil ||
        fileState.currentLocalFolder != nil && fileState.currentLocalFile == nil ||
        fileState.isTemporaryGroupSelected && fileState.currentTemporaryFile == nil
    }
    
    var body: some View {
        ContentDetailNavigationView(isSettingsPresented: $isSettingsPresented)
            .modifier(FileHomeItemTransitionModifier())
            .modifier(ExcalidrawContainerToolbarContentModifier())
            .opacity(fileState.isInCollaborationSpace ? 0 : 1)
            .overlay {
                ExcalidrawCollabContainerView()
                    .opacity(fileState.isInCollaborationSpace ? 1 : 0)
                    .allowsHitTesting(fileState.isInCollaborationSpace)
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
            .environmentObject(toolState)

        // splitViewsContent()
        //     .environmentObject(toolState)
    }
    
    @MainActor @ViewBuilder
    private func splitViewsContent() -> some View {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            ExcalidrawSplitViewsContainer()
        } else if fileState.currentFiles.count > 0 {
            ExcalidrawContainerWrapper(activeFile: $fileState.currentFiles[0])
        }
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
}


struct ContentDetailNavigationView: View {
    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    @Binding var isSettingsPresented: Bool
    
    @StateObject private var toolState = ToolState()

    var disableInteration: Bool {
        !fileState.hasAnyActiveFile && !fileState.hasAnyActiveGroup ||
        fileState.currentGroup != nil && fileState.currentFile == nil ||
        fileState.currentLocalFolder != nil && fileState.currentLocalFile == nil ||
        fileState.isTemporaryGroupSelected && fileState.currentTemporaryFile == nil
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
    }
    
    @State private var lastHomeType: HomeType = .home
    
    /// For transition
    @State private var currentGroups: [Group] = []
    
    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
            
            ExcalidrawContainerView(interactionEnabled: !disableInteration)
                .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)
                .allowsHitTesting(!disableInteration)
            
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
                                !fileState.hasAnyActiveFile && !fileState.hasAnyActiveGroup
                                ? 1
                                : 0
                            )
                        
                    case .fileHome:
                        // File Home View
                        ZStack {
                            ForEach(Array(currentGroups.enumerated()), id: \.element) { i, group in
                                FileHomeView(group: group)
                                    .opacity(
                                        fileHomeItemTransitionState.canShowItemContainerView ||
                                        fileState.currentFile == nil
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
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(.separator).frame(width: 1).offset(x: -1)
                                        }
                                    }
                                    .transition(
                                        .move(edge: .trailing)
                                    )
                            }
                        }
                        
                        
                    case .localFileHome:
                        EmptyView()
                    case .temporaryFileHome:
                        EmptyView()
                        
                }
            }
        }
        .onReceive(fileState.objectWillChange) { _ in
            guard fileState.currentFile == nil else { return }
            
            lastHomeType = fileState.currentGroup != nil ? .fileHome :
                fileState.currentLocalFolder != nil ? .localFileHome :
                fileState.isTemporaryGroupSelected ? .temporaryFileHome : .home
        }
        .onChange(of: fileState.currentFile) { newValue in
            if newValue == nil, currentGroups.isEmpty, let currentGroup = fileState.currentGroup {
                // file all parents
                var parents: [Group] = [currentGroup]
                var p = currentGroup
                while let parent = p.parent {
                    parents.append(parent)
                    p = parent
                }
                currentGroups = parents.reversed()
            }
        }
        .watchImmediately(of: fileState.currentGroup) { newValue in
            if let newValue, lastHomeType == .fileHome {
                if currentGroups.isEmpty {
                    // file all parents
                    var parents: [Group] = [newValue]
                    var p = newValue
                    while let parent = p.parent {
                        parents.append(parent)
                        p = parent
                    }
                    currentGroups = parents.reversed()
                } else if currentGroups.contains(newValue) {
                    let index = currentGroups.firstIndex(of: newValue)!
                    withAnimation(.smooth(duration: 0.4)) {
                        currentGroups = Array(currentGroups.prefix(upTo: index + 1))
                    }
                } else {
                    withAnimation(.smooth(duration: 0.4)) {
                        currentGroups.append(newValue)
                    }
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                        currentGroups.remove(at: 0)
//                    }
                }
            } else {
                currentGroups.removeAll()
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
        FlexibleSplitView(items: $fileState.currentFiles) { file in
            withAnimation {
                fileState.currentFiles.removeAll(where: {$0.id == file.id})
            }
        } subView: { activeFile in
            ExcalidrawContainerWrapper(activeFile: activeFile)
        }
    }
}


struct ExcalidrawContainerWrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState

    @Binding var activeFile: FileState.ActiveFile
    
    var body: some View {
        ExcalidrawContainerView(
            file: Binding<ExcalidrawFile?> {
                switch activeFile {
                    case .file(let file):
                        return try? ExcalidrawFile(from: file.objectID, context: viewContext)
                    case .localFile(let url):
                        return try? ExcalidrawFile(contentsOf: url)
                    case .temporaryFile(let url):
                        return try? ExcalidrawFile(contentsOf: url)
                    case .collaborationFile(let file):
                        return try? ExcalidrawFile(from: file.objectID, context: viewContext)
                }
            } set: { val in
                guard let val else { return }
                do {
                    switch activeFile {
                        case .file(let file):
                            if file.id?.uuidString == activeFile.id {
                                // Everytime load a new file will cause an actual update.
                                let oldElements = try ExcalidrawFile(
                                    from: file.objectID,
                                    context: viewContext
                                ).elements
                                if val.elements == oldElements {
                                    print("[updateCurrentFile] no updates, ignored.")
                                    return
                                } else {
                                    print("[updateCurrentFile] elements changed.")
                                }
                                fileState.updateFile(file, with: val)
                            }
                        case .localFile(let url):
                            guard let folder = fileState.currentLocalFolder else { return }
                            Task {
                                try folder.withSecurityScopedURL { _ in
                                    do {
                                        let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                        if val.elements == oldElements {
                                            print("[updateCurrentFile] no updates, ignored.")
                                            return
                                        } else {
                                            print("[updateCurrentFile] elements changed.")
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
                                    } else {
                                        print("[updateCurrentFile] elements changed.")
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
                        case .collaborationFile(let file):
                            print("Not support yet...")
                    }
                } catch {
                    
                }
            }
        )
        .modifier(ExcalidrawContainerToolbarContentModifier())
        .opacity(fileState.isInCollaborationSpace ? 0 : 1)
        .overlay {
            ExcalidrawCollabContainerView()
                .opacity(fileState.isInCollaborationSpace ? 1 : 0)
                .allowsHitTesting(fileState.isInCollaborationSpace)
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
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        
    } else {
        EmptyView()
    }
}

