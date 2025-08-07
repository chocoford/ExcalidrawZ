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

    
//    {
//        Binding {
//            do {
//                if let file = fileState.currentFile {
//                    let excalidrawFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
//                    return excalidrawFile
//                } else if let folder = fileState.currentLocalFolder,
//                          let file = fileState.currentLocalFile,
//                          let folderPath = folder.url?.filePath,
//                          file.filePath.contains(folderPath) {
//                    // Should startAccessingSecurityScopedResource for folderURL
//                    let file = try folder.withSecurityScopedURL { _ in
//                        return try ExcalidrawFile(contentsOf: file)
//                    }
//                    return file
//                } else if fileState.isTemporaryGroupSelected,
//                          let file = fileState.currentTemporaryFile {
//                    return try ExcalidrawFile(contentsOf: file)
//                }
//            } catch {
//                alertToast(error)
//            }
//            return nil
//        } set: { file in
//            guard let file else { return }
//            if let currentFile = fileState.currentFile,
//                  file.id == fileState.currentFile?.id {
//                do {
//                    // Everytime load a new file will cause an actual update.
//                    let oldElements = try ExcalidrawFile(from: currentFile.objectID, context: viewContext).elements
//                    if file.elements == oldElements {
//                        print("[updateCurrentFile] no updates, ignored.")
//                        return
//                    } else {
//                        print("[updateCurrentFile] elements changed.")
//                    }
//                } catch {
//                    alertToast(error)
//                }
//                fileState.updateCurrentFile(with: file)
//            } else if let folder = fileState.currentLocalFolder,
//                      let url = fileState.currentLocalFile {
//                Task {
//                    do {
//                        try folder.withSecurityScopedURL { _ in
//                            do {
//                                let oldElements = try ExcalidrawFile(contentsOf: url).elements
//                                if file.elements == oldElements {
//                                    print("[updateCurrentFile] no updates, ignored.")
//                                    return
//                                } else {
//                                    print("[updateCurrentFile] elements changed.")
//                                }
//                                try await fileState.updateLocalFile(to: url, with: file, context: viewContext)
//                            } catch {
//                                alertToast(error)
//                            }
//                        }
//                    } catch {
//                        alertToast(error)
//                    }
//                }
//            } else if fileState.isTemporaryGroupSelected,
//                      let url = fileState.currentTemporaryFile {
//                Task {
//                    do {
//                        let oldElements = try ExcalidrawFile(contentsOf: url).elements
//                        if file.elements == oldElements {
//                            print("[updateCurrentFile] no updates, ignored.")
//                            return
//                        } else {
//                            print("[updateCurrentFile] elements changed.")
//                        }
//                        try await fileState.updateLocalFile(to: url, with: file, context: viewContext)
//                    } catch {
//                        alertToast(error)
//                    }
//                }
//            }
//        }
//    }

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
            } else if fileState.currentFile?.inTrash == true {
                recoverOverlayView
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .top) {
            if isImporting, loadingState == .loaded, fileState.currentGroup != nil {
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
                        DispatchQueue.main.async {
                            if event.type == .import, !event.succeeded {
                                isImporting = true
                                if let file = fileState.currentFile {
                                    self.fileBeforeImporting = try? ExcalidrawFile(
                                        from: file.objectID,
                                        context: viewContext
                                    )
                                }
                            }
                            if event.type == .import, event.succeeded, isImporting {
                                isImporting = false
                                if let file = fileState.currentFile,
                                   let fileAfterImporting = try? ExcalidrawFile(from: file.objectID, context: viewContext) {
                                     
                                    if fileBeforeImporting?.elements == fileAfterImporting.elements {
                                      // do nothing
                                    } else if Set(fileAfterImporting.elements).isSubset(of: Set(fileBeforeImporting?.elements ?? [])) {
                                        // if local changes is all beyond cloud, do nothing
                                    } else {
                                        // force reload current file.
                                        fileState.excalidrawWebCoordinator?.loadFile(from: fileState.currentFile, force: true)
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
                .localizable(.deletedFileRecoverAlertTitle),
                isPresented: $layoutState.isResotreAlertIsPresented
            ) {
                Button(role: .cancel) {
                    layoutState.isResotreAlertIsPresented.toggle()
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonCancel))
                }
                
                Button {
                    // Recover file
                    if let currentFile = fileState.currentFile {
                        fileState.recoverFile(currentFile)
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
        .onChange(
            of: fileState.currentLocalFile == nil && fileState.currentFile == nil && fileState.currentTemporaryFile == nil && !fileState.isInCollaborationSpace,
            debounce: 0.1
        ) { newValue in
            isSelectFilePlaceholderPresented = newValue
        }
        .contentShape(Rectangle())
    }
    
    @MainActor @ViewBuilder
    private func emptyFilePlaceholderview() -> some View {
        selectFilePlaceholderView()
    }
}

