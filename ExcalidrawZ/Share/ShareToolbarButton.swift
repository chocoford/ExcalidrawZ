//
//  ShareToolbarButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

import ChocofordUI

class ShareFileState: ObservableObject {
    enum ShareTarget {
        case image, file
    }
    
    @Published var currentSharedFile: ExcalidrawFile? {
        didSet {
            if currentSharedFile == nil {
                shareTarget = nil
            }
        }
    }
    @Published var shareTarget: ShareTarget?
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
        if fileState.currentActiveFile == nil {
            return true
        }
        if fileState.activeCollaborationFileIsLoading {
            return true
        }
        if case .group(let group) = fileState.currentActiveGroup {
            return group.groupType == .trash
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
            await syncCurrentCanvasBeforeSharingIfNeeded()
            switch fileState.currentActiveFile {
                case .file(let file):
                    let content = try await file.loadContent()
                    let excalidrawFile = try ExcalidrawFile(
                        data: content,
                        id: file.id?.uuidString
                    )
                    self.shareFileState.currentSharedFile = excalidrawFile
                case .localFile(let url):
                    if case .localFolder(let folder) = fileState.currentActiveGroup {
                        try await folder.withSecurityScopedURL { (_: URL) async throws -> Void in
                            self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: url)
                        }
                    }
                case .temporaryFile(let url):
                    let content = try await fileState.readTemporaryFileContent(at: url)
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(
                        data: content,
                        id: fileState.currentActiveFile?.id
                    )
                    
                case .collaborationFile(let collaborationFile):
                    let content = try await collaborationFile.loadContent()
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(
                        data: content,
                        id: collaborationFile.id?.uuidString
                    )
                case .cloudStorageFile(let reference):
                    let content = try await CloudStorageDocumentStore.shared.content(
                        for: reference,
                        checkingRemoteRevision: false
                    )
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(
                        data: content,
                        id: reference.id
                    )
                default:
                    break
            }
        } catch {
            alertToast(error)
        }
    }

    @MainActor
    private func syncCurrentCanvasBeforeSharingIfNeeded() async {
        await fileState.excalidrawWebCoordinator?.documentSyncController
            .flushPendingDirtySnapshot(reason: "shareToolbar")
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
