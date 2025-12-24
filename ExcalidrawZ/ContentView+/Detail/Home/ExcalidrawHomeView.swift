//
//  ExcalidrawHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI

struct ExcalidrawHomeView: View {
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
                                GroupFileHomeView(group: group, sortField: fileState.sortField)
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
                                    LocalFolderFileHomeView(folder: folder, sortField: fileState.sortField)
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
        .overlay(alignment: .bottomTrailing) {
            SyncStatusPopover()
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
