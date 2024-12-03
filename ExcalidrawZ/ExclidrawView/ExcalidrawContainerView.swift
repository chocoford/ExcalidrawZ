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
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState

    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var isLoading = true
    @State private var isProgressViewPresented = true
    
    @State private var isDropping: Bool = false
    @State private var cloudContainerEventChangeListener: AnyCancellable?

    var fileBinding: Binding<ExcalidrawFile> {
        Binding {
            if let file = fileState.currentFile {
                do {
                    let excalidrawFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
                    
                    return excalidrawFile
                } catch {
                    alertToast(error)
                    print(error)
                    return ExcalidrawFile()
                }
            } else {
                return ExcalidrawFile()
            }
        } set: { file in
            guard let currentFile = fileState.currentFile,
                  file.id == fileState.currentFile?.id else {
                return
            }
            do {
                // Everytime load a new file will cause an actual update.
                let oldElements = try ExcalidrawFile(from: currentFile.objectID, context: viewContext).elements
                if file.elements == oldElements {
                    print("[updateCurrentFile] no updates, ignored.")
                    return
                } else {
                    print("[updateCurrentFile] elements changed.")
                }
            } catch {
                alertToast(error)
            }
            fileState.updateCurrentFile(with: file)
        }
    }
    
    // everytime launch should sync data.
    @State private var isImporting = false
    @State private var fileBeforeImporting: ExcalidrawFile?
    
    var body: some View {
        ZStack(alignment: .center) {
            ExcalidrawView(
                file: fileBinding,
                isLoadingPage: $isLoading
            ) { error in
                alertToast(error)
                print(error)
            }
            .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
            .opacity(isProgressViewPresented ? 0 : 1)
            .onChange(of: isLoading, debounce: 1) { newVal in
                isProgressViewPresented = newVal
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
            if isImporting, !isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Syncing data...")
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
            self.cloudContainerEventChangeListener = NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).sink { notification in
                if let userInfo = notification.userInfo {
                    if let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event {
                        DispatchQueue.main.async {
                            if event.type == .import, !event.succeeded {
                                isImporting = true
                                if let file = fileState.currentFile {
                                    self.fileBeforeImporting = try? ExcalidrawFile(from: file.objectID, context: viewContext)
                                }
                            }
                            if event.type == .import, event.succeeded, isImporting {
                                isImporting = false
                                if let file = fileState.currentFile,
                                   let fileAfterImporting = try? ExcalidrawFile(from: file.objectID, context: viewContext),
                                   fileAfterImporting.elements != fileBeforeImporting?.elements {
                                    // force reload current file.
                                    print("force reload current file...")
                                    fileState.excalidrawWebCoordinator?.loadFile(from: fileState.currentFile, force: true)
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
}


#if DEBUG
#Preview {
    ExcalidrawContainerView()
        .frame(width: 800, height: 600)
}
#endif
