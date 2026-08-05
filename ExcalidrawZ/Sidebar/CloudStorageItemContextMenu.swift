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
    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared

    let location: CloudStorageLocation
    let presentation: Presentation

    enum Presentation {
        case contextMenu
        case fileHomeMenu
    }

    init(
        location: CloudStorageLocation,
        presentation: Presentation = .contextMenu
    ) {
        self.location = location
        self.presentation = presentation
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
            case .contextMenu:
                content.contextMenu {
                    removeConnectionButton
                }
            case .fileHomeMenu:
                Menu {
                    removeConnectionButton
#if os(iOS)
                    Divider()
                    CloudStorageFileHomeSelectionMenuItem()
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
        "Remove \(location.providerID.displayName) Connection"
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
            documentStore.removeCachedState(for: location.id)
            connections.removeLocation(location)
        }
    }
}

struct CloudStorageFileContextMenuModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var fileState: FileState

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared

    let reference: CloudStorageDocumentReference

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

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    open()
                } label: {
                    Label(.localizable(.generalButtonOpen), systemSymbol: .arrowUpRightSquare)
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
        let activeFileID = fileState.currentActiveFile?.id
        Task {
            do {
                try await documentStore.deleteDocuments(references)
                if let activeFileID,
                   references.contains(where: { $0.id == activeFileID }) {
                    fileState.setActiveFile(nil)
                }
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
        presentation: Presentation = .contextMenu
    ) {
        self.folder = folder
        self.presentation = presentation
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
                        Divider()
                        CloudStorageFileHomeSelectionMenuItem()
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
                try await documentStore.deleteFolder(folder)
                if fileState.currentActiveGroup == .cloudStorageFolder(folder) {
                    fileState.setActiveFile(nil)
                    fileState.setActiveGroupIfNeeded(
                        parent.map(FileState.ActiveGroup.cloudStorageFolder)
                    )
                }
            } catch {
                alertToast(error)
            }
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
