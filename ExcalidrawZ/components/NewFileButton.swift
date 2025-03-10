//
//  NewFileButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

extension Notification.Name {
    static let shouldHandleNewDraw = Notification.Name("ShouldHandleNewDraw")
    static let shouldHandleNewDrawFromClipboard = Notification.Name("ShouldHandleNewDrawFromClipboard")
    
}

struct NewFileButton: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @Environment(\.alert) private var alert
    @EnvironmentObject private var fileState: FileState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    init() {}
    
    var body: some View {
        Menu {
            Button {
                createNewFile()
            } label: {
                Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Button {
                createNewFileFromClipboard()
            } label: {
                Label("New draw from clipboard", systemSymbol: .squareAndPencil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
        } label: {
            Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
        } primaryAction: {
            createNewFile()
        }
        .bindWindow($window)
        .help(.localizable(.createNewFile))
        .disabled(fileState.currentGroup?.groupType == .trash)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDraw)) { _ in
            guard window?.isKeyWindow == true else { return }
            
            self.createNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDrawFromClipboard)) { _ in
            guard window?.isKeyWindow == true else { return }

            self.createNewFileFromClipboard()
        }
    }
    
    private func createNewFile() {
        do {
            if fileState.currentGroup != nil {
                try fileState.createNewFile(context: viewContext)
            } else if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { scopedURL in
                    do {
                        try await fileState.createNewLocalFile(folderURL: scopedURL)
                    } catch {
                        alertToast(error)
                    }
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func createNewFileFromClipboard() {
        Task {
            do {
#if canImport(AppKit)
                guard let pngData = NSPasteboard.general.data(forType: .png) else {
                    struct CanNotReadFromClipboardError: LocalizedError {
                        var errorDescription: String? {
                            "Can not read from clipboard"
                        }
                    }
                    throw CanNotReadFromClipboardError()
                }
#elseif canImport(UIKit)
                let image = UIPasteboard.general.image
                guard let pngData = image?.pngData() else {
                    struct CanNotReadFromClipboardError: LocalizedError {
                        var errorDescription: String? {
                            "Can not read from clipboard"
                        }
                    }
                    throw CanNotReadFromClipboardError()
                }
#endif
                if fileState.currentGroup != nil {
                    try fileState.createNewFile(context: viewContext)
                } else if let folder = fileState.currentLocalFolder {
                    try await folder.withSecurityScopedURL { scopedURL in
                        do {
                            try await fileState.createNewLocalFile(folderURL: scopedURL)
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                
                try await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))
                // drop clipboard data to current file
                try await fileState.excalidrawWebCoordinator?.loadImageToExcalidrawCanvas(imageData: pngData, type: "png")
            } catch {
                alert(error: error)
            }
        }
    }
}

#Preview {
    NewFileButton()
}

