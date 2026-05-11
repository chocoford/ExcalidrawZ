//
//  LocalFileContextMenu.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/7/25.
//

import SwiftUI
import CoreData
import ChocofordUI

struct LocalFileMenuProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState

    var file: URL?
    var content: (Triggers) -> AnyView

    init<Content: View>(
        file: URL?,
        content: @escaping (Triggers) -> Content
    ) {
        self.file = file
        self.content = { AnyView(content($0)) }
    }
    
    
    struct Triggers {
        var onToggleRename: () -> Void
    }
    
    @State private var isRenameSheetPresented = false
    
    var triggers: Triggers {
        Triggers {
            isRenameSheetPresented.toggle()
        }
    }
    
    private var files: Set<URL> {
        if let file {
            if fileState.selectedLocalFiles.contains(file) {
                return fileState.selectedLocalFiles
            }
            return [file]
        }
        return fileState.selectedLocalFiles
    }
    
    private var firstFile: URL? {
        files.first
    }
    
    var body: some View {
        content(triggers)
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenameSheetPresented,
                    name: firstFile?.deletingPathExtension().lastPathComponent ?? ""
                ) { newName in
                    guard let file = firstFile else { return }
                    renameFile(file: file, newName: newName)
                }
            )
    }
    
    private func renameFile(file: URL, newName: String) {
        do {
            // find folder
            let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            fetchRequest.predicate = NSPredicate(format: "filePath == %@", file.deletingLastPathComponent().filePath)
            guard let folder = try viewContext.fetch(fetchRequest).first else { return }
            
            try folder.withSecurityScopedURL { _ in
                let newURL = file.deletingLastPathComponent()
                    .appendingPathComponent(
                        newName,
                        conformingTo: .excalidrawFile
                    )
                try FileManager.default.moveItem(at: file, to: newURL)
                
                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil
                
                // Also update checkpoints
                updateCheckpoints(oldURL: file, newURL: newURL)
                rebindAIConversations(oldURL: file, newURL: newURL)
                
                localFolderState.itemRenamedPublisher.send(newURL.filePath)
            }
            
        } catch {
            alertToast(error)
        }
    }

    private func rebindAIConversations(oldURL: URL, newURL: URL) {
        Task.detached {
            do {
                try await PersistenceController.shared.aiConversationRepository.rebindConversations(
                    from: AIConversationFileScope(kind: .localFile, id: oldURL.absoluteString),
                    to: AIConversationFileScope(kind: .localFile, id: newURL.absoluteString)
                )
            } catch {
                print("Warning: Failed to rebind AI conversations for renamed local file: \(error)")
            }
        }
    }
    
    private func updateCheckpoints(oldURL: URL, newURL: URL) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
                    fetchRequest.predicate = NSPredicate(format: "url = %@", oldURL as NSURL)
                    let checkpoints = try context.fetch(fetchRequest)
                    checkpoints.forEach {
                        $0.url = newURL
                    }
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct LocalFileRowContextMenuModifier: ViewModifier {
    var file: URL
    
    func body(content: Content) -> some View {
        LocalFileMenuProvider(file: file) { triggers in
            content
                .contextMenu {
                    LocalFileRowMenuItems(file: file) {
                        triggers.onToggleRename()
                    }
                    .labelStyle(.titleAndIcon)
                }
        }
    }
}

struct LocalFileMenu: View {
    var file: URL?
    var label: AnyView
    
    init<Label: View>(
        file: URL?,
        @ViewBuilder label: () -> Label
    ) {
        self.file = file
        self.label = AnyView(label())
    }
    
    var body: some View {
        LocalFileMenuProvider(file: file) { triggers in
            Menu {
                LocalFileRowMenuItems(file: file) {
                    triggers.onToggleRename()
                }
            } label: {
                label
            }
        }
    }
}

struct LocalFileRowMenuItems: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState

    var file: URL?
    var onToggleRename: () -> Void

    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    private var files: Set<URL> {
        if let file {
            if fileState.selectedLocalFiles.contains(file) {
                return fileState.selectedLocalFiles
            }
            return [file]
        }
        return fileState.selectedLocalFiles
    }
    
    private var isSingleFile: Bool {
        files.count == 1
    }
    
    private var firstFile: URL? {
        files.first
    }
    
    var body: some View {
        if containerHorizontalSizeClass != .compact {
            var isInEditMode: Bool {
#if os(iOS)
                editMode?.wrappedValue == .active
#else
                false
#endif
            }
            
            // Open
            if !isInEditMode,
               let file = firstFile,
               fileState.currentActiveFile != .localFile(file) {
                Button {
                    if let firstFile {
                        fileState.setActiveFile(.localFile(firstFile))
                    }
                } label: {
                    Label(
                        .localizable(.generalButtonOpen),
                        systemSymbol: .arrowUpRightSquare
                    )
                }
                .disabled(!isSingleFile)
            }
            // Download / Remove download
            if let firstFile, isSingleFile {
                FileStatusProvider(file: .localFile(firstFile)) { fileStatus in
                    if fileStatus?.iCloudStatus == .conflict {
                        
                    } else if fileStatus?.iCloudStatus == .downloaded {
                        AsyncButton {
                            try await FileCoordinator.shared.evictLocalCopy(of: firstFile)
                        } label: {
                            Label(
                                "Remove download",
                                systemSymbol: .xmarkCircle
                            )
                        }
                    } else if fileStatus?.iCloudStatus == .outdated {
                        AsyncButton {
                            try await FileCoordinator.shared.downloadFile(url: firstFile)
                        } label: {
                            Label(
                                "Download",
                                systemSymbol: .icloudAndArrowDown
                            )
                        }
                    }
                    
                }
            }
        }
        
        // Rename
        Button {
            onToggleRename()
        } label: {
            Label(
                .localizable(.sidebarFileRowContextMenuRename),
                systemSymbol: .squareAndPencil
            )
        }
        .disabled(!isSingleFile)


        Button {
            duplicateFile()
        } label: {
            Label {
                if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                    Text(
                        localizable: .sidebarFileRowContextMenuDuplicateFiles(files.count)
                    )
                } else {
                    Text(localizable: .sidebarFileRowContextMenuDuplicate)
                }
            } icon: {
                Image(systemSymbol: .docOnDoc)
            }
        }

        moveLocalFileMenu()
        
#if os(macOS)
        Button {
#if canImport(AppKit)
            NSPasteboard.general.clearContents()
            if let firstFile {
                NSPasteboard.general.setString(firstFile.filePath, forType: .string)
            }
#elseif canImport(UIKit)
            if let firstFile {
                UIPasteboard.general.setObjects([firstFile.filePath])
            }
#endif
        } label: {
            Label(.localizable(.sidebarLocalFileRowContextMenuCopyPath), systemSymbol: .arrowRightDocOnClipboard)
                .foregroundStyle(.red)
        }
        .disabled(!isSingleFile)

        Button {
            let filesToReveal = Array(files)
            guard !filesToReveal.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(filesToReveal)
        } label: {
            Label(
                .localizable(
                    .generalButtonRevealInFinder
                ),
                systemSymbol: .docViewfinder
            )
            .foregroundStyle(.red)
        }
#endif
        Divider()
        
        // Delete
        Button {
            moveToTrash()
        } label: {
            Label {
                if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                    Text(
                        localizable: .generalButtonMoveFilesToTrash(files.count)
                    )
                } else {
                    Text(localizable: .generalButtonMoveToTrash)
                }
            } icon: {
                Image(systemSymbol: .trash)
            }
            .foregroundStyle(.red)
        }
    }
    
    
    @MainActor @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        if case .localFolder(let currentLocalFolder) = fileState.currentActiveGroup {
            Menu {
                ForEach(topLevelLocalFolders) { folder in
                    MoveToGroupMenu(
                        destination: folder,
                        sourceGroup: currentLocalFolder,
                        childrenSortKey: \LocalFolder.filePath,
                        allowSubgroups: true
                    ) { targetFolderID in
                        moveLocalFile(to: targetFolderID)
                    }
                }
            } label: {
                
                Label {
                    if #available(macOS 13.0, iOS 16.0, *) {
                        if files.count > 1 {
                            Text(
                                localizable: .generalMoveFilesTo(
                                    files.count
                                )
                            )
                        } else {
                            Text(localizable: .generalMoveTo)
                        }
                    } else {
                        Text(localizable: .generalMoveTo)
                    }
                } icon: {
                    Image(systemSymbol: .trayAndArrowUp)
                }
            }
        }
    }
    
    
    private func duplicateFile() {
        let filesToDuplicate = Array(files)
        var fileToBeActive: URL? = nil

        Task {
            do {
                guard case .localFolder(let folder) = fileState.currentActiveGroup else { return }
                try await folder.withSecurityScopedURL { scopedURL async throws in

                    for sourceFile in filesToDuplicate {

                        let file = try ExcalidrawFile(contentsOf: sourceFile)

                        var newFileName = sourceFile.deletingPathExtension().lastPathComponent
                        while FileManager.default.fileExists(at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)) {
                            let components = newFileName.components(separatedBy: "-")
                            if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                                newFileName = "\(components[0])-\(index+1)"
                            } else {
                                newFileName = "\(newFileName)-1"
                            }
                        }

                        let newURL = sourceFile.deletingLastPathComponent().appendingPathComponent(newFileName, conformingTo: .excalidrawFile)

                        // Use FileCoordinator for safe atomic write
                        guard let data = file.content else { continue }
                        try await FileCoordinator.shared.coordinatedWrite(url: newURL, data: data)

                        if filesToDuplicate.count == 1,
                           filesToDuplicate[0] == sourceFile {
                            fileToBeActive = newURL
                        }
                    }

                    await MainActor.run {
                        if let fileToBeActive,
                           let sourceFile = filesToDuplicate.first,
                           fileState.currentActiveFile == .localFile(sourceFile) {
                            fileState.setActiveFile(.localFile(fileToBeActive))
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let filesToMove = Array(files)
        let currentActiveFile: URL? = if case .localFile(let currentFile) = fileState.currentActiveFile {
            currentFile
        } else { nil }

        Task {
            do {
                let mapping = try await LocalFileUtils.moveLocalFiles(filesToMove, to: targetFolderID, context: context)

                if let currentActiveFile, let newURL = mapping[currentActiveFile] {
                    await MainActor.run {
                        fileState.setActiveFile(.localFile(newURL))
                    }
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
        }
    }
    
    private func moveToTrash() {
        let filesToDelete = Array(files)

        Task {
            do {
                if case .localFolder(let folder) = fileState.currentActiveGroup {
                    try await folder.withSecurityScopedURL { _ async throws in
                        // Item removed will be handled in `LocalFilesListView`
                        for file in filesToDelete {
                            _ = try await FileCoordinator.shared.coordinatedTrash(url: file)
                            do {
                                try await PersistenceController.shared.aiConversationRepository
                                    .deleteConversations(
                                        forFileScope: AIConversationFileScope(
                                            kind: .localFile,
                                            id: file.absoluteString
                                        )
                                    )
                            } catch {
                                print("Warning: Failed to delete AI conversations for local file \(file): \(error)")
                            }
                        }
                    }

                    await MainActor.run {
                        if let currentActiveFile = {
                            if case .localFile(let file) = fileState.currentActiveFile {
                                return file
                            }
                            return nil
                        }(), filesToDelete.contains(currentActiveFile) {
                            fileState.setActiveFile(nil)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
        }
    }
}
