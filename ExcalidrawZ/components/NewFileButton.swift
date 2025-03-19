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
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isFileImporterPresented = false
    
    init() {}
    
    var body: some View {
#if os(iOS)
        if fileState.currentGroup != nil {
            Button {
                isFileImporterPresented.toggle()
            } label: {
                Label(.localizable(.menubarButtonImport), systemSymbol: .squareAndArrowDown)
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.excalidrawFile],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    // Should hanlde here...
                    Task.detached {
                        do {
                            try await fileState.importFiles(urls)
                        } catch {
                            print(error)
                            await alertToast(error)
                        }
                    }
                } else if case .failure(let error) = result {
                    alertToast(error)
                }
            }
        }
#endif
        
        if fileState.isInCollaborationSpace {
            collaborationNewButton()
        } else {
            localNewButton()
        }
    }
    
    @MainActor @ViewBuilder
    private func localNewButton() -> some View {
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
                // TODO: Temp, change it next version.
                Label(.localizable(.whatsNewNewDrawFromClipboardTitle), systemSymbol: .squareAndPencil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
        } label: {
            Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
        } primaryAction: {
            createNewFile()
        }
        .bindWindow($window)
        .help(.localizable(.createNewFile))
        .disabled(fileState.currentGroup?.groupType == .trash || fileState.isTemporaryGroupSelected)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDraw)) { _ in
            guard window?.isKeyWindow == true else { return }
            
            self.createNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDrawFromClipboard)) { _ in
            guard window?.isKeyWindow == true else { return }

            self.createNewFileFromClipboard()
        }
    }
    
    @MainActor @ViewBuilder
    private func collaborationNewButton() -> some View {
//        if containerHorizontalSizeClass == .compact {
//            Button {
//                
//            } label: {
//                if #available(macOS 13.0, *) {
//                    Label("New room", systemSymbol: .doorLeftHandOpen)
//                } else {
//                    Label("New room", systemSymbol: .plus)
//                }
//            }
//        } else {
        Menu {
            Button {
                collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
            } label: {
                Label("Create a room", systemSymbol: .plus)
            }
            Button {
                collaborationState.isJoinRoomSheetPresented.toggle()
            } label: {
                Label("Join a room", systemSymbol: .ipadAndArrowForward)
            }
        } label: {
            if #available(macOS 13.0, *) {
                Label("New room", systemSymbol: .doorLeftHandOpen)
            } else {
                Label("New room", systemSymbol: .plus)
            }
        }
        .help("New room")
        .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
//        }
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

