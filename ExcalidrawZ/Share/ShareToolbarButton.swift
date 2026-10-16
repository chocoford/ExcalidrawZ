//
//  ShareToolbarButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI
import CoreData
import SwiftyAlert

import ChocofordUI

struct ImageExportContext {
    var selectedElementIDs: Set<String> = []
    var coordinator: ExcalidrawCore? = nil
}

class ShareFileState: ObservableObject {
    enum ShareTarget {
        case image, file
    }
    
    @Published var currentSharedFile: ExcalidrawFile? {
        didSet {
            if currentSharedFile == nil {
                shareTarget = nil
                imageExportContext = .init()
            }
        }
    }
    @Published var shareTarget: ShareTarget?
    var imageExportContext = ImageExportContext()
}

struct ShareToolbarButton: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var shareFileState: ShareFileState
    @EnvironmentObject private var exportState: ExportState

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif

#if os(macOS)
    @State private var isSharing = false
#endif
    
    
#if os(iOS)
    @State private var exportedPDFURL: URL?
#endif

    private var isShareDisabled: Bool {
        guard let activeFile = fileState.currentActiveFile else {
            return true
        }
        if fileState.activeCollaborationFileIsLoading {
            return true
        }
        if case .file(let file) = activeFile {
            return file.inTrash
        }
        return false
    }
    
    var body: some View {
#if os(macOS)
        Button {
            Task { @MainActor in
                await performShareFileWithLoading()
            }
        } label: {
            Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
                .opacity(isSharing ? 0 : 1)
                .overlay {
                    if isSharing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .help(String(localizable: .export))
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(isShareDisabled || isSharing)
        .bindWindow($window)
        .onReceive(NotificationCenter.default.publisher(for: .toggleShare)) { notification in
            guard window?.isKeyWindow == true,
                  !isShareDisabled else { return }
            Task { @MainActor in
                await performShareFileWithLoading()
            }
        }
#else
        Menu {
            Button {
                Task {
                    shareFileState.shareTarget = .image
                    await performShareFile()
                }
            } label: {
                Label(.localizable(.exportSheetButtonImage), systemSymbol: .photo)
            }
            
            Button {
                Task {
                    shareFileState.shareTarget = .file
                    await performShareFile()
                }
            } label: {
                Label(.localizable(.exportSheetButtonFile), systemSymbol: .doc)
            }
            
            Button {
                Task {
                    do {
                        let imageData = try await exportState.exportCurrentFileToImage(
                            type: .svg,
                            embedScene: false,
                            withBackground: true,
                            colorScheme: .light
                        )
                        exportedPDFURL = await exportPDF(name: imageData.name, svgURL: imageData.url)
                    } catch {
                        alertToast(error)
                    }
                }
            } label: {
                Label(.localizable(.exportSheetButtonPDF), systemSymbol: .docRichtext)
            }
            
        } label: {
            Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
        }
        .disabled(isShareDisabled)
        .activitySheet(item: $exportedPDFURL)
#endif
    }
    
    @MainActor
    private func performShareFile() async {
        do {
            guard let activeFile = fileState.currentActiveFile else { return }
            let coordinator: ExcalidrawCore?
            if case .collaborationFile = activeFile {
                coordinator = fileState.excalidrawCollaborationWebCoordinator
            } else {
                coordinator = fileState.excalidrawWebCoordinator
                if let coordinator {
                    guard try await coordinator.documentSyncController.waitUntilFileIsLoaded(
                        activeFile.id,
                        timeout: 15
                    ) else {
                        throw ExcalidrawPreviewExportError.timedOut("Export document", 15)
                    }
                }
            }
            guard fileState.currentActiveFile?.id == activeFile.id else { return }
            let selectedIDs = (try? await coordinator?.getSelectedElementIDs())
                ?? coordinator?.selectedElementIDs ?? []
            await coordinator?.documentSyncController
                .flushPendingDirtySnapshot(reason: "shareToolbar")
            guard fileState.currentActiveFile?.id == activeFile.id else { return }
            var sharedFile: ExcalidrawFile?
            if let coordinator {
                // Stored library documents omit media. Export a live snapshot so recently
                // edited elements and their image resources stay together.
                let snapshot = try await coordinator.getCurrentFileSnapshot()
                guard var document = try JSONSerialization.jsonObject(with: snapshot.documentData()) as? [String: Any] else {
                    throw CocoaError(.coderReadCorrupt)
                }
                document["type"] = "excalidraw"
                sharedFile = try ExcalidrawFile(
                    data: JSONSerialization.data(withJSONObject: document),
                    id: activeFile.id
                )
            } else {
                switch activeFile {
                    case .file(let file):
                        let content = try await file.loadContent()
                        sharedFile = try ExcalidrawFile(
                            data: content,
                            id: file.id?.uuidString
                        )
                    case .localFile(let url):
                        sharedFile = try await LocalFolder.withSecurityScopedAccessToContainingFolder(
                            for: url
                        ) {
                            try ExcalidrawFile(contentsOf: url)
                        }
                    case .temporaryFile(let url):
                        let content = try await fileState.readTemporaryFileContent(at: url)
                        sharedFile = try ExcalidrawFile(
                            data: content,
                            id: activeFile.id
                        )
                    case .collaborationFile(let collaborationFile):
                        let content = try await collaborationFile.loadContent()
                        sharedFile = try ExcalidrawFile(
                            data: content,
                            id: collaborationFile.id?.uuidString
                        )
                    case .cloudStorageFile(let reference):
                        let content = try await CloudStorageDocumentStore.shared.content(
                            for: reference,
                            checkingRemoteRevision: false
                        )
                        sharedFile = try ExcalidrawFile(
                            data: content,
                            id: reference.id
                        )
                }
            }
            guard var sharedFile,
                  fileState.currentActiveFile?.id == activeFile.id else { return }
            sharedFile.name = activeFile.name
            shareFileState.imageExportContext = ImageExportContext(
                selectedElementIDs: Set(selectedIDs),
                coordinator: coordinator
            )
            self.shareFileState.currentSharedFile = sharedFile
        } catch {
            alertToast(error)
        }
    }

#if os(macOS)
    @MainActor
    private func performShareFileWithLoading() async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        await performShareFile()
    }
#endif
}
