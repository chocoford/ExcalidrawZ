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
    
    
#if os(iOS)
    @State private var exportedPDFURL: URL?
#endif
    
    var body: some View {
#if os(macOS)
        AsyncButton {
            await performShareFile()
        } label: {
            Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
        }
        .help(String(localizable: .export))
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(
            {
                if case .group(let group) = fileState.currentActiveGroup {
                    return group.groupType == .trash
                }
                return false
            }() ||
            fileState.currentActiveFile == nil
        )
        .bindWindow($window)
        .onReceive(NotificationCenter.default.publisher(for: .toggleShare)) { notification in
            guard window?.isKeyWindow == true else { return }
            Task {
                await performShareFile()
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
        .activitySheet(item: $exportedPDFURL)
#endif
    }
    
    @MainActor
    private func performShareFile() async {
        print("[performShareFile] Thread: \(Thread())")
        do {
            switch fileState.currentActiveFile {
                case .file(let file):
                    let content = try await file.loadContent()
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(data: content, id: file.id)
                case .localFile(let url):
                    if case .localFolder(let folder) = fileState.currentActiveGroup {
                        try await folder.withSecurityScopedURL { (_: URL) async throws -> Void in
                            self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: url)
                        }
                    }
                case .temporaryFile(let url):
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: url)
                    
                case .collaborationFile(let collaborationFile):
                    let content = try await collaborationFile.loadContent()
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(data: content, id: collaborationFile.id)
                default:
                    break
            }
        } catch {
            alertToast(error)
        }
    }
}

