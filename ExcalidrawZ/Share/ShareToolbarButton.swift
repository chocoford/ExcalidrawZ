//
//  ShareToolbarButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

import ChocofordUI

class ShareFileState: ObservableObject {
    @Published var currentSharedFile: ExcalidrawFile?
}

struct ShareToolbarButton: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var shareFileState: ShareFileState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    var body: some View {
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

