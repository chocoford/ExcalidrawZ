//
//  ExcalidrawCollaborationView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

import ChocofordUI

struct ExcalidrawCollaborationView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    var file: CollaborationFile

    init(file: CollaborationFile) {
        self.file = file
    }
    
    var isActive: Bool {
        if fileState.isInCollaborationSpace,
           case .collaborationFile(let room) = fileState.currentActiveFile {
            return room == file
        } else {
            return false
        }
    }
    
    @State private var loadingState: ExcalidrawView.LoadingState = .idle
    @State private var isProgressViewPresented = true

    @State private var excalidrawFile: ExcalidrawFile?

    var body: some View {
        ZStack {
            if excalidrawFile != nil {
                ExcalidrawView(
                    type: .collaboration,
                    file: $excalidrawFile,
                    loadingState: $loadingState,
                    interactionEnabled: isActive
                ) { error in
                    alertToast(error)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .opacity(isProgressViewPresented ? 0 : 1)
                .onChange(of: loadingState, debounce: 0.3) { newVal in
                    isProgressViewPresented = newVal == .loading
                    
                    fileState.collaboratingFilesState[file] = newVal
                    
                    if newVal == .loaded {
                        Task {
                            do {
                                try await fileState.excalidrawCollaborationWebCoordinator?
                                    .setCollaborationInfo(
                                        collaborationState.userCollaborationInfo
                                    )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
                .onChange(of: collaborationState.userCollaborationInfo, debounce: 1.0) { newInfo in
                    Task {
                        do {
                            try await fileState.excalidrawCollaborationWebCoordinator?.setCollaborationInfo(
                                newInfo
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .onChange(of: excalidrawFile, throttle: 1.0, latest: true) { newValue in
                    guard let newValue, loadingState == .loaded else { return }
                    fileState.updateCurrentCollaborationFile(with: newValue)
                }
            }
            
            if case .error(let error) = loadingState {
                Color(red: 255 / 255.0, green: 200 / 255.0, blue: 200 / 255.0, opacity: 1.0)
                    .overlay {
                        VStack(spacing: 20) {
                            Image(systemSymbol: .xmark)
                                .resizable()
                                .scaledToFit()
                                .symbolVariant(.circle)
                                .foregroundStyle(.red)
                                .frame(height: 80)
                            
                            Text("Load failed.")
                                .font(.title)
                            if let error = error as? LocalizedError {
                                Text(error.errorDescription ?? error.localizedDescription)
                            } else {
                                Text(error.localizedDescription)
                            }
                            Button {
                                fileState.excalidrawCollaborationWebCoordinator?.refresh()
                            } label: {
                                Text("Reload")
                                    .padding(.horizontal)
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                        }
                    }

            } else if isProgressViewPresented {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(.localizable(.webViewLoadingText))
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .task {
            do {
                // Load content from CollaborationFile
                let content = try await file.loadContent()
                var excalidrawFile = try ExcalidrawFile(data: content, id: file.id?.uuidString)
                excalidrawFile.roomID = file.roomID
                try await excalidrawFile.syncFiles(context: viewContext)
                await MainActor.run {
                    self.excalidrawFile = excalidrawFile
                    fileState.updateCurrentCollaborationFile(with: excalidrawFile)
                }
            } catch {
                // Fallback to empty file if loading fails
                var excalidrawFile = ExcalidrawFile()
                excalidrawFile.id = file.id?.uuidString ?? UUID().uuidString
                excalidrawFile.roomID = file.roomID
                try? await excalidrawFile.syncFiles(context: viewContext)
                await MainActor.run {
                    self.excalidrawFile = excalidrawFile
                }
                alertToast(error)
            }
        }
        .onDisappear {
            fileState.collaboratingFilesState[file] = nil
        }
    }
}
