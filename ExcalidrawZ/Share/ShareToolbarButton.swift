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
            fileState.currentGroup?.groupType == .trash ||
            (
                fileState.currentFile == nil &&
                fileState.currentLocalFile == nil &&
                fileState.currentTemporaryFile == nil &&
                fileState.currentCollaborationFile == nil
            )
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
            if let file = fileState.currentFile ?? fileState.currentCollaborationFile?.room {
                self.shareFileState.currentSharedFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
            } else if let folder = fileState.currentLocalFolder,
                let fileURL = fileState.currentLocalFile {
                try folder.withSecurityScopedURL { _ in
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: fileURL)
                }
            } else if fileState.isTemporaryGroupSelected,
                      let fileURL = fileState.currentTemporaryFile {
                self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: fileURL)
            }
        } catch {
            alertToast(error)
        }
    }
}

