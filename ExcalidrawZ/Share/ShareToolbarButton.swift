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
        Button {
            performShareFile()
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
            performShareFile()
        }
    }
    
    @MainActor
    private func performShareFile() {
        print("[performShareFile] Thread: \(Thread.current)")
        do {
            switch fileState.currentActiveFile {
                case .file(let file):
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
                case .localFile(let url):
                    if case .localFolder(let folder) = fileState.currentActiveGroup {
                        try folder.withSecurityScopedURL { _ in
                            self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: url)
                        }
                    }
                case .temporaryFile(let url):
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: url)

                case .collaborationFile(let collaborationFile):
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(from: collaborationFile.objectID, context: viewContext)
                default:
                    break
            }
        } catch {
            alertToast(error)
        }
    }
}

