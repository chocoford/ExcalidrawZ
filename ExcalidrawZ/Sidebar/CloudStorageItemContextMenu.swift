//
//  CloudStorageItemContextMenu.swift
//  ExcalidrawZ
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(iOS)
private struct CloudStorageFileHomeSelectionMenuItem: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var fileState: FileState

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            Button {
                withAnimation(.smooth) {
                    editMode?.wrappedValue = .inactive
                }
                fileState.resetSelections()
            } label: {
                Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
            }
        } else {
            Button {
                withAnimation(.smooth) {
                    editMode?.wrappedValue = .active
                }
            } label: {
                Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
            }
        }
    }
}
#endif

struct CloudStorageLocationActionsModifier: ViewModifier {
    @EnvironmentObject private var fileState: FileState

    @ObservedObject private var connections = CloudStorageConnectionStore.shared

    let location: CloudStorageLocation
    let presentation: Presentation
    let showsSelection: Bool
    let showsSwipeActions: Bool

    enum Presentation {
        case contextMenu
        case fileHomeMenu
    }

    init(
        location: CloudStorageLocation,
        presentation: Presentation = .contextMenu,
        showsSelection: Bool = true,
        showsSwipeActions: Bool = false
    ) {
        self.location = location
        self.presentation = presentation
        self.showsSelection = showsSelection
        self.showsSwipeActions = showsSwipeActions
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
            case .contextMenu:
                let menuContent = content.contextMenu {
                    removeConnectionButton
                }

                if showsSwipeActions {
                    menuContent
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            removeConnectionButton
                                .tint(.red)
                        }
                } else {
                    menuContent
                }
            case .fileHomeMenu:
                Menu {
                    removeConnectionButton
#if os(iOS)
                    if showsSelection {
                        Divider()
                        CloudStorageFileHomeSelectionMenuItem()
                    }
#endif
                } label: {
                    content
                }
        }
    }

    private var removeConnectionButton: some View {
        Button(role: .destructive) {
            removeConnection()
        } label: {
            Label(removeActionTitle, systemImage: "trash")
        }
    }

    private var removeActionTitle: String {
        String(
            localized: "cloudStorageActionUnlink",
            defaultValue: "Unlink"
        )
    }

    private func removeConnection() {
        Task { @MainActor in
            if case .cloudStorageFile(let reference) = fileState.currentActiveFile,
               reference.locationID == location.id {
                guard await fileState.requestActiveFileChange(nil) else { return }
            }

            if case .cloudStorageFolder(let folder) = fileState.currentActiveGroup,
               folder.location.id == location.id {
                fileState.setActiveGroupIfNeeded(nil)
            }
            fileState.resetSelections()
            await CloudStorageSyncService.shared.removeConnection(
                for: location,
                connections: connections
            )
        }
    }
}

struct CloudStorageFileActionsModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var fileState: FileState

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared

    let reference: CloudStorageDocumentReference
    let presentation: Presentation

    enum Presentation {
        case contextMenu
        case fileMenu
    }

    init(
        reference: CloudStorageDocumentReference,
        presentation: Presentation = .contextMenu
    ) {
        self.reference = reference
        self.presentation = presentation
    }

    @State private var isRenamePresented = false
    @State private var isDeletePresented = false
    @State private var isConflictResolutionPresented = false

    private var selectedReferences: Set<CloudStorageDocumentReference> {
        if fileState.selectedCloudStorageFiles.contains(reference) {
            return fileState.selectedCloudStorageFiles
        }
        return [reference]
    }

    private func selectedReferencesAllow(
        _ capability: CloudStorageItemCapabilities
    ) -> Bool {
        selectedReferences.allSatisfy {
            documentStore.capabilities(for: $0).contains(capability)
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
            case .contextMenu:
                withPresentations(
                    content.contextMenu {
                        fileActionItems
                    }
                )
            case .fileMenu:
                withPresentations(
                    Menu {
                        fileActionItems
                    } label: {
                        content
                    }
                )
        }
    }

    @ViewBuilder
    private var fileActionItems: some View {
        if !isCurrentFile {
            Button {
                open()
            } label: {
                Label(.localizable(.generalButtonOpen), systemSymbol: .arrowUpRightSquare)
            }
        }

        if case .conflict = documentStore.syncState(for: reference) {
            Button {
                isConflictResolutionPresented = true
            } label: {
                Label(
                    String(
                        localized: "cloudStorageConflictResolveAction",
                        defaultValue: "Resolve Conflict…"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }

        if selectedReferences.count == 1,
           selectedReferencesAllow(.rename) {
            Button {
                isRenamePresented = true
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .pencil)
            }
        }

        if selectedReferencesAllow(.download) {
            Button {
                duplicateSelectedFiles()
            } label: {
                Label {
                    if selectedReferences.count > 1 {
                        Text(
                            localizable: .sidebarFileRowContextMenuDuplicateFiles(
                                selectedReferences.count
                            )
                        )
                    } else {
                        Text(localizable: .sidebarFileRowContextMenuDuplicate)
                    }
                } icon: {
                    Image(systemSymbol: .plusSquareOnSquare)
                }
            }
        }

        Divider()

        Button {
            revealInProvider()
        } label: {
            Label(
                .localizable(
                    .cloudStorageContextMenuShowInProvider(
                        reference.providerID.displayName
                    )
                ),
                systemImage: "safari"
            )
        }

        Button {
            copyRemoteLink()
        } label: {
            Label(.localizable(.cloudStorageContextMenuCopyLink), systemImage: "link")
        }

        if selectedReferencesAllow(.delete) {
            Divider()

            Button(role: .destructive) {
                isDeletePresented = true
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDelete), systemSymbol: .trash)
            }
        }
    }

    private var isCurrentFile: Bool {
        guard case .cloudStorageFile(let activeReference) = fileState.currentActiveFile else {
            return false
        }
        return activeReference == reference
    }

    private func withPresentations<PresentedContent: View>(
        _ content: PresentedContent
    ) -> some View {
        content
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenamePresented,
                    name: FileState.ActiveFile.cloudStorageFile(reference).name
                        ?? reference.lastKnownName
                ) { name in
                    rename(to: name)
                }
            )
            .sheet(isPresented: $isConflictResolutionPresented) {
                CloudStorageConflictResolutionSheetView(reference: reference)
            }
            .confirmationDialog(
                String(
                    localizable: .sidebarFileRowDeletePermanentlyAlertTitle(
                        FileState.ActiveFile.cloudStorageFile(reference).name
                            ?? reference.lastKnownName
                    )
                ),
                isPresented: $isDeletePresented
            ) {
                Button(role: .destructive) {
                    deleteSelectedFiles()
                } label: {
                    Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm))
                }
            } message: {
                Text(.localizable(.generalCannotUndoMessage))
            }
    }

    private func open() {
        if let parent = documentStore.parentFolder(for: reference) {
            fileState.setActiveGroupIfNeeded(.cloudStorageFolder(parent))
        }
        fileState.setActiveFile(.cloudStorageFile(reference))
    }

    private func rename(to name: String) {
        Task {
            do {
                let updated = try await documentStore.renameDocument(
                    reference,
                    to: name
                )
                fileState.replaceCloudStorageDocumentReference(updated)
                fileState.resetSelections()
            } catch {
                alertToast(error)
            }
        }
    }

    private func duplicateSelectedFiles() {
        let references = selectedReferences
        Task {
            do {
                _ = try await documentStore.duplicateDocuments(references)
                fileState.resetSelections()
            } catch {
                alertToast(error)
            }
        }
    }

    private func revealInProvider() {
        Task {
            do {
                openURL(try await documentStore.remoteURL(for: reference))
            } catch {
                alertToast(error)
            }
        }
    }

    private func copyRemoteLink() {
        Task {
            do {
                copyCloudStorageURLToPasteboard(
                    try await documentStore.remoteURL(for: reference)
                )
                alertToast(
                    .init(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .exportActionCopied)
                    )
                )
            } catch {
                alertToast(error)
            }
        }
    }

    private func deleteSelectedFiles() {
        let references = selectedReferences
        Task {
            do {
                guard await fileState.closeActiveFileIfDeleting(
                    anyOf: references
                ) else {
                    return
                }
                try await documentStore.deleteDocuments(references)
                fileState.resetSelections()
            } catch {
                alertToast(error)
            }
        }
    }
}

struct CloudStorageFolderActionsModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var fileState: FileState

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared

    let folder: CloudStorageFolderReference
    let presentation: Presentation
    let showsSelection: Bool

    @State private var isRenamePresented = false
    @State private var isDeletePresented = false
    @State private var isCreateFolderPresented = false
    @State private var newFolderName = ""

    enum Presentation {
        case contextMenu
        case fileHomeMenu
    }

    init(
        folder: CloudStorageFolderReference,
        presentation: Presentation = .contextMenu,
        showsSelection: Bool = true
    ) {
        self.folder = folder
        self.presentation = presentation
        self.showsSelection = showsSelection
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
            case .contextMenu:
                withPresentations(
                    content.contextMenu {
                        folderActionItems
                    }
                )
            case .fileHomeMenu:
                withPresentations(
                    Menu {
                        folderActionItems
#if os(iOS)
                        if showsSelection {
                            Divider()
                            CloudStorageFileHomeSelectionMenuItem()
                        }
#endif
                    } label: {
                        content
                    }
                )
        }
    }

    @ViewBuilder
    private var folderActionItems: some View {
        Button {
            fileState.setActiveGroupIfNeeded(.cloudStorageFolder(folder))
        } label: {
            Label(.localizable(.generalButtonOpen), systemSymbol: .arrowUpRightSquare)
        }

        if capabilities.contains(.rename) {
            Button {
                isRenamePresented = true
            } label: {
                Label(.localizable(.sidebarGroupRowContextMenuRename), systemSymbol: .pencil)
            }
        }

        if capabilities.contains(.createChildren) {
            Button {
                newFolderName = documentStore.availableFolderName(in: folder)
                isCreateFolderPresented = true
            } label: {
                Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .folderBadgePlus)
            }
        }

        Divider()

        Button {
            revealInProvider()
        } label: {
            Label(
                .localizable(
                    .cloudStorageContextMenuShowInProvider(
                        folder.location.providerID.displayName
                    )
                ),
                systemImage: "safari"
            )
        }

        Button {
            copyRemoteLink()
        } label: {
            Label(.localizable(.cloudStorageContextMenuCopyLink), systemImage: "link")
        }

        if capabilities.contains(.delete) {
            Divider()

            Button(role: .destructive) {
                isDeletePresented = true
            } label: {
                Label(.localizable(.sidebarGroupRowContextMenuDelete), systemSymbol: .trash)
            }
        }
    }

    private var capabilities: CloudStorageItemCapabilities {
        documentStore.capabilities(for: folder)
    }

    private func withPresentations<PresentedContent: View>(
        _ content: PresentedContent
    ) -> some View {
        content
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenamePresented,
                    name: folder.name
                ) { name in
                    rename(to: name)
                }
            )
            .sheet(isPresented: $isCreateFolderPresented) {
                CreateGroupSheetView(
                    name: $newFolderName,
                    createType: .localFolder
                ) { name in
                    createFolder(named: name)
                }
                .controlSize(.large)
#if os(macOS)
                .frame(width: 400, height: 140)
#endif
            }
            .confirmationDialog(
                String(localizable: .sidebarGroupRowDeleteConfirmTitle(folder.name)),
                isPresented: $isDeletePresented
            ) {
                Button(role: .destructive) {
                    deleteFolder()
                } label: {
                    Text(.localizable(.sidebarGroupRowDeleteButton))
                }
            } message: {
                Text(.localizable(.sidebarGroupRowDeleteMessage))
            }
    }

    private func rename(to name: String) {
        Task {
            do {
                let updated = try await documentStore.renameFolder(
                    folder,
                    to: name
                )
                if fileState.currentActiveGroup == .cloudStorageFolder(folder) {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(updated))
                }
            } catch {
                alertToast(error)
            }
        }
    }

    private func createFolder(named name: String) {
        Task {
            do {
                _ = try await documentStore.createFolder(named: name, in: folder)
            } catch {
                alertToast(error)
            }
        }
    }

    private func revealInProvider() {
        Task {
            do {
                openURL(try await documentStore.remoteURL(for: folder))
            } catch {
                alertToast(error)
            }
        }
    }

    private func copyRemoteLink() {
        Task {
            do {
                copyCloudStorageURLToPasteboard(
                    try await documentStore.remoteURL(for: folder)
                )
                alertToast(
                    .init(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .exportActionCopied)
                    )
                )
            } catch {
                alertToast(error)
            }
        }
    }

    private func deleteFolder() {
        Task {
            do {
                let parent = documentStore.folderPath(for: folder)
                    .dropLast()
                    .last
                guard await closeActiveFileIfContainedInFolder() else {
                    return
                }
                try await documentStore.deleteFolder(folder)
                if activeGroupIsContainedInFolder {
                    fileState.setActiveGroupIfNeeded(
                        parent.map(FileState.ActiveGroup.cloudStorageFolder)
                    )
                }
            } catch {
                alertToast(error)
            }
        }
    }

    @MainActor
    private func closeActiveFileIfContainedInFolder() async -> Bool {
        guard case .cloudStorageFile(let activeReference) = fileState.currentActiveFile,
              activeReference.locationID == folder.location.id else {
            return true
        }
        let parentContainsFolder = documentStore.parentFolder(for: activeReference)
            .map { parent in
                documentStore.folderPath(for: parent).contains {
                    $0.itemID == folder.itemID
                }
            } ?? false
        guard parentContainsFolder || activeGroupIsContainedInFolder else { return true }
        return await fileState.closeActiveFileIfDeleting(anyOf: [activeReference])
    }

    @MainActor
    private var activeGroupIsContainedInFolder: Bool {
        guard case .cloudStorageFolder(let activeFolder) = fileState.currentActiveGroup,
              activeFolder.location.id == folder.location.id else {
            return false
        }
        return documentStore.folderPath(for: activeFolder).contains {
            $0.itemID == folder.itemID
        }
    }
}

private func copyCloudStorageURLToPasteboard(_ url: URL) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
#elseif os(iOS)
    UIPasteboard.general.url = url
#endif
}
