//
//  NewFileButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI
import CoreData

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

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState
    @EnvironmentObject private var localFolderState: LocalFolderState
    @ObservedObject private var cloudStorageDocumentStore = CloudStorageDocumentStore.shared
    
    
    var usesFileHomeOpenTransition: Bool
    
    init(
        usesFileHomeOpenTransition: Bool = false
    ) {
        self.usesFileHomeOpenTransition = usesFileHomeOpenTransition
    }

    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isFileImporterPresented = false
    
    @FetchRequest(sortDescriptors: [])
    private var collaborationFiles: FetchedResults<CollaborationFile>
    
    var body: some View {
#if os(iOS)
        if canShowImportButton, containerHorizontalSizeClass != .compact {
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
    
    private var canShowImportButton: Bool {
        guard case .group(let group) = fileState.currentActiveGroup else {
            return false
        }
        return group.groupType != .trash
    }

    @ViewBuilder
    private func localNewButton() -> some View {
        Menu {
            Button {
                createNewFile()
            } label: {
                Label(.localizable(.generalButtonCreateNewFile), systemSymbol: .squareAndPencil)
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
            ZStack {
                Label(.localizable(.generalButtonCreateNewFile), systemSymbol: .squareAndPencil)
                    .opacity(isCreatingFile ? 0.0 : 1.0)
                
                if isCreatingFile {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
        } primaryAction: {
            createNewFile()
        }
        .fixedSize()
        .bindWindow($window)
        .help(.localizable(.generalButtonCreateNewFile))
        .disabled({
            if case .group(let group) = fileState.currentActiveGroup, group.groupType == .trash {
                return true
            }
            return false
        }() || cannotCreateInActiveCloudStorageFolder
            || fileState.currentActiveGroup == .temporary
            || isCreatingFile)
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDraw)) { _ in
            guard window?.isKeyWindow == true else { return }
            
            self.createNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldHandleNewDrawFromClipboard)) { _ in
            guard window?.isKeyWindow == true else { return }

            self.createNewFileFromClipboard()
        }
    }
    
    @ViewBuilder
    private func collaborationNewButton() -> some View {
        Menu {
            Button {
                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                    store.togglePaywall(reason: .roomLimit)
                } else {
                    collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
                }
            } label: {
                Label(.localizable(.collaborationButtonCreateNewRoom), systemSymbol: .plus)
            }
            Button {
                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                    store.togglePaywall(reason: .roomLimit)
                } else {
                    collaborationState.isJoinRoomSheetPresented.toggle()
                }
            } label: {
                Label(.localizable(.collaborationButtonJoinRoom), systemSymbol: .ipadAndArrowForward)
            }
        } label: {
            if #available(macOS 13.0, *) {
                Label(.localizable(.toolbarButtonCollaborationNewRoom), systemSymbol: .doorLeftHandOpen)
            } else {
                Label(.localizable(.toolbarButtonCollaborationNewRoom), systemSymbol: .plus)
            }
        }
        .help(.localizable(.toolbarButtonCollaborationNewRoom))
        .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
    }
    
    @State private var isCreatingFile = false

    private var cannotCreateInActiveCloudStorageFolder: Bool {
        guard case .cloudStorageFolder(let folder) = fileState.currentActiveGroup else {
            return false
        }
        return !cloudStorageDocumentStore.capabilities(for: folder).contains(.createChildren)
    }
    
    private func createNewFile() {
        guard !isCreatingFile else { return }
        
        isCreatingFile = true
        
        Task {
            do {
                if case .group(let group) = fileState.currentActiveGroup {
                    createFile(in: group.objectID, delay: 0)
                } else if case .localFolder(let folder) = fileState.currentActiveGroup {
                    try await folder.withSecurityScopedURL { scopedURL in
                        do {
                            guard let url = try await fileState.createNewLocalFile(
                                active: !usesFileHomeOpenTransition,
                                folderURL: scopedURL
                            ) else {
                                await MainActor.run {
                                    isCreatingFile = false
                                }
                                return
                            }
                            await MainActor.run {
                                localFolderState.itemCreatedPublisher.send(url.filePath)

                                if usesFileHomeOpenTransition {
                                    fileState.setActiveFile(.localFile(url))
                                }
                                isCreatingFile = false
                            }
                        } catch {
                            await MainActor.run {
                                isCreatingFile = false
                                alertToast(error)
                            }
                        }
                    }
                } else if case .cloudStorageFolder(let folder) = fileState.currentActiveGroup {
                    let reference = try await CloudStorageDocumentStore.shared.createDocument(
                        in: folder
                    )
                    await MainActor.run {
                        fileState.setActiveFile(.cloudStorageFile(reference))
                        isCreatingFile = false
                    }
                } else if let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: viewContext) {
                    createFile(in: defaultGroup.objectID, delay: 0)
                } else {
                    await MainActor.run {
                        isCreatingFile = false
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingFile = false
                    alertToast(error)
                }
            }
        }
    }
    
    private func createFile(in groupID: NSManagedObjectID, delay: TimeInterval) {
        Task {
            do {
                let fileID = try await fileState.createNewFile(
                    active: !usesFileHomeOpenTransition,
                    in: groupID,
                    context: viewContext
                )
                try await viewContext.perform {
                    if let file = viewContext.object(with: fileID) as? File {
                        file.visitedAt = .now
                    }
                    try viewContext.save()
                }
                
                if usesFileHomeOpenTransition, delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if let file = viewContext.object(with: fileID) as? File {
                            fileState.setActiveFile(.file(file))
                        }
                        isCreatingFile = false
                    }
                } else {
                    await MainActor.run {
                        if usesFileHomeOpenTransition,
                           let file = viewContext.object(with: fileID) as? File {
                            fileState.setActiveFile(.file(file))
                        }
                        isCreatingFile = false
                    }
                }
                
                let activeGroupUpdateDelay = (usesFileHomeOpenTransition ? delay : 0) + 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + activeGroupUpdateDelay) {
                    if let group = viewContext.object(with: groupID) as? Group {
                        fileState.currentActiveGroup = .group(group)
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingFile = false
                    alertToast(error)
                }
            }
        }
    }
    
    private func createNewFileFromClipboard() {
        Task {
            do {
#if canImport(AppKit)
                guard let pngData = NSPasteboard.general.data(forType: .png) else {
                    struct CanNotReadFromClipboardError: LocalizedError {
                        var errorDescription: String? {
                            String(localizable: .pasteboardErrorNoData)
                        }
                    }
                    throw CanNotReadFromClipboardError()
                }
#elseif canImport(UIKit)
                let image = UIPasteboard.general.image
                guard let pngData = image?.pngData() else {
                    struct CanNotReadFromClipboardError: LocalizedError {
                        var errorDescription: String? {
                            String(localizable: .pasteboardErrorNoData)
                        }
                    }
                    throw CanNotReadFromClipboardError()
                }
#endif
                
                if case .group(let group) = fileState.currentActiveGroup {
                    try await fileState.createNewFile(
                        in: group.objectID,
                        context: viewContext,
                    )
                } else if case .localFolder(let folder) = fileState.currentActiveGroup {
                    try await folder.withSecurityScopedURL { scopedURL in
                        do {
                            if let url = try await fileState.createNewLocalFile(folderURL: scopedURL) {
                                localFolderState.itemCreatedPublisher.send(url.filePath)
                            }
                        } catch {
                            alertToast(error)
                        }
                    }
                } else if case .cloudStorageFolder(let folder) = fileState.currentActiveGroup {
                    let reference = try await CloudStorageDocumentStore.shared.createDocument(
                        in: folder
                    )
                    fileState.setActiveFile(.cloudStorageFile(reference))
                } else {
                    let defaultGroup = try await viewContext.perform {
                        try PersistenceController.shared.getDefaultGroup(
                            context: viewContext
                        )
                    }
                    if let defaultGroup {
                        try await fileState.createNewFile(
                            in: defaultGroup.objectID,
                            context: viewContext,
                        )
                    }
                }
                
                try await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))
                // drop clipboard data to current file
                try await fileState.excalidrawWebCoordinator?.loadImageToExcalidrawCanvas(
                    imageData: pngData,
                    type: "png"
                )
            } catch {
                alert(error: error)
            }
        }
    }
}

struct ImportFileProvider: View {
    
    
    var body: some View {
        
    }
}

struct ImportFileButton: View {
    var body: some View {
        
    }
}

#Preview {
    NewFileButton()
}
