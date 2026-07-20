//
//  ExcalidrawHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawHomeView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    @Binding var isSettingsPresented: Bool

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
    @State private var renderedGroups: [Group] = []
    @State private var renderedFolders: [LocalFolder] = []
    
    @State private var isTransitioning = false
    @State private var folderTransitionGeneration = 0
    private let folderNavigationTransitionDuration: TimeInterval = 0.4
    private let folderNavigationCleanupDelay: TimeInterval = 0.5
    
    var body: some View {
        ZStack {
            homeLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(fileHomeItemTransitionState.canShowItemContainerView)
                .accessibilityHidden(!fileHomeItemTransitionState.canShowItemContainerView)
                .zIndex(fileHomeItemTransitionState.canShowItemContainerView ? 1 : 0)

            editorLayer
                .allowsHitTesting(
                    !disableInteration &&
                    !fileHomeItemTransitionState.canShowItemContainerView
                )
                .zIndex(fileHomeItemTransitionState.canShowItemContainerView ? 0 : 1)
        }
            .overlay(alignment: .bottomTrailing) {
                if fileHomeItemTransitionState.canShowItemContainerView {
                    SyncStatusPopover()
                }
            }
            .overlay(alignment: .top) {
                ActiveFileCloseSavingIndicator(
                    isSaving: fileState.isFinalizingActiveFileClose
                )
            }
            .watch(value: fileState.currentActiveFile) { newValue in
                if newValue == nil {
                    initCurrentGroups()

                    updateLastHomeType()
                }
            }
            .watch(value: fileState.currentActiveGroup, initial: true) { _, newValue in
                handleActiveGroupChanged(newValue)
            }
            .watch(value: fileHomeItemTransitionState.canShowItemContainerView) { isVisible in
                guard !isVisible, fileState.currentActiveFile != nil else { return }
                initCurrentGroups()
                updateLastHomeType()
            }
    }

    private var editorLayer: some View {
        ExcalidrawEditor(
            activeFile: fileState.activeFileBinding,
            interactionEnabled: !disableInteration
        )
        .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)
    }

    private var homeLayer: some View {
        ZStack {
//            background
//                .ignoresSafeArea()
//                .opacity(disableInteration || !fileHomeItemTransitionState.canShowExcalidrawCanvas ? 0 : 1)

            Color.clear
            
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
                            ForEach(Array(renderedGroups.enumerated()), id: \.element) { i, group in
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
                                            color: .gray.opacity(isTransitioning && i == renderedGroups.endIndex - 1 ? 0.3 : 0.0),
                                            radius: 0,
                                            x: -1
                                        )
                                        .animation(
                                            .default,
                                            value: isTransitioning && i == renderedGroups.endIndex - 1
                                        )
                                    }
                                    .transition(
                                        .move(edge: .trailing)
                                    )
                                    .zIndex(Double(i))
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .trailing)
                            )
                        )
                case .localFileHome:
                        ZStack {
                            LocalFoldersProvider { _ in
                                ForEach(Array(renderedFolders.enumerated()), id: \.element) { i, folder in
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
                                                color: .gray.opacity(isTransitioning && i == renderedFolders.endIndex - 1 ? 0.3 : 0.0),
                                                radius: 0,
                                                x: -1
                                            )
                                            .animation(
                                                .default,
                                                value: isTransitioning && i == renderedFolders.endIndex - 1
                                            )
                                        }
                                        .transition(
                                            .move(edge: .trailing)
                                        )
                                        .zIndex(Double(i))
                                }
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .trailing)
                            )
                        )
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

    private func handleActiveGroupChanged(_ newValue: FileState.ActiveGroup?) {
        switch newValue {
            case .group(let newValue):
                currentFolders.removeAll()
                renderedFolders.removeAll()

                if currentGroups.isEmpty {
                    initCurrentGroups()
                } else if currentGroups.contains(newValue) {
                    let index = currentGroups.firstIndex(of: newValue)!
                    let previousGroup = currentGroups.last
                    let targetGroups = Array(currentGroups.prefix(upTo: index + 1))
                    if previousGroup == newValue {
                        currentGroups = targetGroups
                        renderedGroups = Array(targetGroups.suffix(1))
                    } else {
                        startFolderTransition()
                        if let previousGroup {
                            renderedGroups = [newValue, previousGroup]
                        }
                        withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                            currentGroups = targetGroups
                            renderedGroups = [newValue]
                        }
                        resetFolderTransitionStateForGroups()
                    }
                } else {
                    let previousGroup = currentGroups.last
                    let targetGroups = currentGroups + [newValue]
                    startFolderTransition()
                    if let previousGroup {
                        renderedGroups = [previousGroup]
                    }
                    currentGroups = targetGroups
                    DispatchQueue.main.async {
                        withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                            if let previousGroup {
                                renderedGroups = [previousGroup, newValue]
                            } else {
                                renderedGroups = [newValue]
                            }
                        }
                        resetFolderTransitionStateForGroups()
                    }
                }

            case .localFolder(let newValue):
                currentGroups.removeAll()
                renderedGroups.removeAll()

                if currentFolders.isEmpty {
                    initCurrentGroups()
                } else if currentFolders.contains(newValue) {
                    let index = currentFolders.firstIndex(of: newValue)!
                    let previousFolder = currentFolders.last
                    let targetFolders = Array(currentFolders.prefix(upTo: index + 1))
                    if previousFolder == newValue {
                        currentFolders = targetFolders
                        renderedFolders = Array(targetFolders.suffix(1))
                    } else {
                        startFolderTransition()
                        if let previousFolder {
                            renderedFolders = [newValue, previousFolder]
                        }
                        withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                            currentFolders = targetFolders
                            renderedFolders = [newValue]
                        }
                        resetFolderTransitionStateForFolders()
                    }
                } else {
                    let previousFolder = currentFolders.last
                    let targetFolders = currentFolders + [newValue]
                    startFolderTransition()
                    if let previousFolder {
                        renderedFolders = [previousFolder]
                    }
                    currentFolders = targetFolders
                    DispatchQueue.main.async {
                        withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                            if let previousFolder {
                                renderedFolders = [previousFolder, newValue]
                            } else {
                                renderedFolders = [newValue]
                            }
                        }

                        resetFolderTransitionStateForFolders()
                    }
                }

            default:
                if lastHomeType == .fileHome,
                   !renderedGroups.isEmpty {
                    startFolderTransition()
                    currentGroups.removeAll()
                    withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                        updateLastHomeType()
                    }
                    resetHomeTransitionStateForGroups()
                    return
                } else if lastHomeType == .localFileHome,
                          !renderedFolders.isEmpty {
                    startFolderTransition()
                    currentFolders.removeAll()
                    withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                        updateLastHomeType()
                    }
                    resetHomeTransitionStateForFolders()
                    return
                } else {
                    currentGroups.removeAll()
                    renderedGroups.removeAll()
                    currentFolders.removeAll()
                    renderedFolders.removeAll()
                }
        }

        if fileState.currentActiveFile == nil {
            updateLastHomeType(animated: true)
        } else if !fileHomeItemTransitionState.canShowItemContainerView {
            // Once opening has completed, keep the hidden Home aligned with
            // the active file without replacing the hero transition source.
            updateLastHomeType()
        }
    }

    private func startFolderTransition() {
        folderTransitionGeneration += 1
        isTransitioning = true
    }

    private func resetFolderTransitionStateForGroups() {
        let generation = folderTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + folderNavigationCleanupDelay) {
            guard generation == folderTransitionGeneration else { return }
            isTransitioning = false
            renderedGroups = Array(currentGroups.suffix(1))
        }
    }

    private func resetFolderTransitionStateForFolders() {
        let generation = folderTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + folderNavigationCleanupDelay) {
            guard generation == folderTransitionGeneration else { return }
            isTransitioning = false
            renderedFolders = Array(currentFolders.suffix(1))
        }
    }

    private func resetHomeTransitionStateForGroups() {
        let generation = folderTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + folderNavigationCleanupDelay) {
            guard generation == folderTransitionGeneration else { return }
            isTransitioning = false
            currentGroups.removeAll()
            renderedGroups.removeAll()
        }
    }

    private func resetHomeTransitionStateForFolders() {
        let generation = folderTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + folderNavigationCleanupDelay) {
            guard generation == folderTransitionGeneration else { return }
            isTransitioning = false
            currentFolders.removeAll()
            renderedFolders.removeAll()
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
                renderedGroups = Array(currentGroups.suffix(1))
                
            case .localFolder(let folder):
                // file all parents
                var parents: [LocalFolder] = [folder]
                var p = folder
                while let parent = p.parent {
                    parents.append(parent)
                    p = parent
                }
                currentFolders = parents.reversed()
                renderedFolders = Array(currentFolders.suffix(1))
            
            default:
                currentGroups.removeAll()
                renderedGroups.removeAll()
                currentFolders.removeAll()
                renderedFolders.removeAll()
                break
        }
    }
    
    private func updateLastHomeType(animated: Bool = false) {
        let nextHomeType: HomeType
        switch fileState.currentActiveGroup {
            case .group:
                nextHomeType = .fileHome
            case .localFolder:
                nextHomeType = .localFileHome
            case .temporary:
                nextHomeType = .temporaryFileHome
            case .collaboration:
                nextHomeType = .collaborationFileHome
            default:
                nextHomeType = .home
        }

        guard lastHomeType != nextHomeType else { return }

        if animated {
            withAnimation(.smooth(duration: folderNavigationTransitionDuration)) {
                lastHomeType = nextHomeType
            }
        } else {
            lastHomeType = nextHomeType
        }
    }
    
}

private struct ActiveFileCloseSavingIndicator: View {
    let isSaving: Bool

    @State private var isPresented = false
    @State private var showTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isPresented {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(.localizable(.activeFileCloseSavingTitle))
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Capsule()
                            .glassEffect(in: Capsule())
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .watch(value: isSaving, initial: true) { saving in
            handleSavingChanged(saving)
        }
        .onDisappear {
            showTask?.cancel()
            showTask = nil
        }
    }

    private func handleSavingChanged(_ saving: Bool) {
        guard saving else {
            showTask?.cancel()
            showTask = nil
            withAnimation(.easeOut(duration: 0.15)) {
                isPresented = false
            }
            return
        }

        showTask?.cancel()
        showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, isSaving else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = true
            }
        }
    }
}
