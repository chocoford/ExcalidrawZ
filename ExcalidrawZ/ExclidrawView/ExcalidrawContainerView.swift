//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import Combine

import ChocofordUI

struct ExcalidrawContainerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass

    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    @Binding var file: ExcalidrawFile?
    var interactionEnabled: Bool
    
    init(
        file: Binding<ExcalidrawFile?>,
        interactionEnabled: Bool = true
    ) {
        self._file = file
        self.interactionEnabled = interactionEnabled
    }

    @State private var loadingState = ExcalidrawView.LoadingState.loading
    @State private var isProgressViewPresented = true
    
    @State private var isDropping: Bool = false
    @State private var cloudContainerEventChangeListener: AnyCancellable?

    // everytime launch should sync data.
    @State private var isImporting = false
    @State private var fileBeforeImporting: ExcalidrawFile?
    
    @State private var isSelectFilePlaceholderPresented = false
    
    var body: some View {
        ZStack(alignment: .center) {
            ExcalidrawView(
                file: $file,
                loadingState: $loadingState,
                interactionEnabled: interactionEnabled,
            ) { error in
                alertToast(error)
            }
            .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
            .opacity(isProgressViewPresented ? 0 : 1)
            .opacity(file == nil ? 0 : 1)
            .onChange(of: loadingState, debounce: 1) { newVal in
                isProgressViewPresented = newVal == .loading
            }
            
            if containerHorizontalSizeClass != .compact {
                selectFilePlaceholderView()
            }
            
            if file == nil {
                emptyFilePlaceholderview()
            }

            if isProgressViewPresented {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(.localizable(.webViewLoadingText))
                }
            } else if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                recoverOverlayView
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .top) {
            if isImporting, loadingState == .loaded, fileState.currentActiveGroup != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(.localizable(.iCloudSyncingDataTitle))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(.regularMaterial)
                }
                .padding()
                .transition(.move(edge: .top))
            }
        }
        .overlay(alignment: .topTrailing) {
            if #available(iOS 17.0, macOS 14.0, *) {
                SyncStatusIndicator()
                    .safeAreaPadding(.all)
            }
        }
        .animation(.easeOut, value: isImporting)
        .transition(.opacity)
        .animation(.default, value: isProgressViewPresented)
        .task {
            self.cloudContainerEventChangeListener?.cancel()
            self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            ).sink { notification in
                if let userInfo = notification.userInfo {
                    if let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event {
                        Task { @MainActor in
                            if event.type == .import, !event.succeeded {
                                isImporting = true
                                if case .file(let file) = fileState.currentActiveFile {
                                    do {
                                        let content = try await file.loadContent()
                                        self.fileBeforeImporting = try ExcalidrawFile(data: content, id: file.id)
                                    } catch {
                                        // Failed to load content, ignore
                                    }
                                }
                            }
                            if event.type == .import, event.succeeded, isImporting {
                                isImporting = false
                                if case .file(let file) = fileState.currentActiveFile {
                                    do {
                                        let content = try await file.loadContent()
                                        let fileAfterImporting = try ExcalidrawFile(data: content, id: file.id)

                                        if fileBeforeImporting?.elements == fileAfterImporting.elements {
                                          // do nothing
                                        } else if Set(fileAfterImporting.elements).isSubset(of: Set(fileBeforeImporting?.elements ?? [])) {
                                            // if local changes is all beyond cloud, do nothing
                                        } else {
                                            // force reload current file.
                                            fileState.excalidrawWebCoordinator?.loadFile(
                                                from: file,
                                                force: true
                                            )
                                        }
                                    } catch {
                                        // Failed to load content, ignore
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                layoutState.isResotreAlertIsPresented.toggle()
            }
            .alert(
                String(localizable: .deletedFileRecoverAlertTitle),
                isPresented: $layoutState.isResotreAlertIsPresented
            ) {
                Button(role: .cancel) {
                    layoutState.isResotreAlertIsPresented.toggle()
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonCancel))
                }
                
                Button {
                    // Recover file
                    if case .file(let currentFile) = fileState.currentActiveFile {
                        Task {
                            let context = viewContext
                            // PersistenceController.shared.container.newBackgroundContext()
                            do {
                                try await fileState
                                    .recoverFile(fileID: currentFile.objectID, context: context)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonRecover))
                }
            } message: {
                Text(.localizable(.deletedFileRecoverAlertMessage))
            }
    }
    
    @MainActor @ViewBuilder
    private func selectFilePlaceholderView() -> some View {
        ZStack {
            if isSelectFilePlaceholderPresented {
                if #available(macOS 14.0, iOS 17.0, *) {
                    Rectangle()
                        .fill(.windowBackground)
                } else {
                    Rectangle()
                        .fill(Color.windowBackgroundColor)
                }
                ProgressView()
            }
        }
        .onChange(of: fileState.currentActiveFile == nil, debounce: 0.1) { newValue in
            isSelectFilePlaceholderPresented = newValue
        }
    }
    
    @MainActor @ViewBuilder
    private func emptyFilePlaceholderview() -> some View {
        ZStack {
            if isSelectFilePlaceholderPresented {
                ZStack {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        Rectangle()
                            .fill(.windowBackground)
                    } else {
                        Rectangle()
                            .fill(Color.windowBackgroundColor)
                    }
                    
                    Text(.localizable(.excalidrawWebViewPlaceholderSelectFile))
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .transition(
                    .asymmetric(
                        insertion: .identity,
                        removal: .opacity.animation(.smooth.delay(0.2))
                    )
                )
            }
        }
        .animation(.default, value: isSelectFilePlaceholderPresented)
        .onChange(of: fileState.currentActiveFile == nil, debounce: 0.1) { newValue in
            isSelectFilePlaceholderPresented = newValue
        }
        .contentShape(Rectangle())
    }
}
