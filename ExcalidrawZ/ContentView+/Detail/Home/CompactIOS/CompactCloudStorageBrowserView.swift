//
//  CompactCloudStorageBrowserView.swift
//  ExcalidrawZ
//

import ChocofordUI
import SwiftUI

#if os(iOS)
struct CompactCloudStorageBrowserView: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState

    let folder: CloudStorageFolderReference

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared
    @StateObject private var browser: CloudStorageSidebarBrowserModel
    @StateObject private var connections = CloudStorageConnectionStore.shared
    @State private var isCreateFolderPresented = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    init(folder: CloudStorageFolderReference) {
        self.folder = folder
        self._browser = StateObject(
            wrappedValue: CloudStorageSidebarBrowserModel(location: folder.location)
        )
    }

    var body: some View {
        ZStack {
            if items != nil {
                CompactBrowserCollectionView(
                    folders: childFolders,
                    files: files
                ) { item in
                    let reference = CloudStorageFolderReference(
                        location: folder.location,
                        item: item
                    )
                    NavigationLink(value: reference) {
                        CompactFolderItemLabel(
                            name: item.name,
                            type: .default,
                            itemsCount: browser.items(
                                in: item.id,
                                sortedBy: fileState.sortField
                            )?.count ?? 0
                        )
                    }
                    .modifier(CloudStorageFolderActionsModifier(folder: reference))
                    .disabled(editMode?.wrappedValue.isEditing == true)
                }
            } else if let errorMessage = browser.errorMessage {
                errorView(errorMessage)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            fileState.currentActiveFile != nil
                || editMode?.wrappedValue.isEditing == true
        )
        .toolbar(content: toolbarContent)
        .sheet(isPresented: $isCreateFolderPresented) {
            CreateGroupSheetView(
                name: $newFolderName,
                createType: .localFolder
            ) { name in
                createFolder(named: name)
            }
            .controlSize(.large)
        }
        .refreshable {
            await browser.refresh(connections: connections)
        }
        .task(id: folder.id) {
            fileState.setActiveGroupIfNeeded(.cloudStorageFolder(folder))
            await CloudStorageSyncService.shared.prioritizeDocumentsAfterUserEntry(
                in: folder.location,
                parentID: folder.itemID,
                connections: connections
            )
        }
        .onDisappear {
            editMode?.wrappedValue = .inactive
            fileState.resetSelections()
        }
    }

    private var items: [CloudStorageItem]? {
        browser.items(in: folder.itemID, sortedBy: fileState.sortField)
    }

    private var childFolders: [CloudStorageItem] {
        items?.filter { $0.kind == .folder } ?? []
    }

    private var files: [FileState.ActiveFile] {
        (items ?? []).compactMap { item in
            guard item.kind == .file else { return nil }
            return .cloudStorageFile(
                CloudStorageDocumentReference(
                    locationID: folder.location.id,
                    providerID: folder.location.providerID,
                    accountID: folder.location.accountID,
                    itemID: item.id,
                    lastKnownName: item.name,
                    lastKnownModifiedAt: item.modifiedAt
                )
            )
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await browser.refresh(connections: connections)
                }
            } label: {
                Text(.localizable(.generalButtonRetry))
            }
            .modernButtonStyle(style: .glass, shape: .modern)
        }
        .padding()
    }

    @MainActor @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            NewFileButton(usesFileHomeOpenTransition: true)
            moreMenu
        }

        ToolbarItem(placement: .navigation) {
            if editMode?.wrappedValue.isEditing == true {
                Button {
                    toggleSelectAllFiles()
                } label: {
                    Text(
                        localizable: allFilesAreSelected
                            ? .generalButtonCancel
                            : .librariesImportSelectAll
                    )
                }
            }
        }

        ToolbarItem(placement: .principal) {
            folderActionsMenu
        }

        ToolbarItemGroup(placement: .bottomBar) {
            if editMode?.wrappedValue.isEditing == true,
               !fileState.selectedCloudStorageFiles.isEmpty {
                Button(role: .destructive) {
                    deleteSelectedFiles()
                } label: {
                    Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                }
            }
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        if editMode?.wrappedValue.isEditing == true {
            Button {
                editMode?.wrappedValue = .inactive
                fileState.resetSelections()
            } label: {
                Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
                    .labelStyle(.iconOnly)
            }
            .modernButtonStyle(style: .glassProminent)
        } else {
            Menu {
                Section {
                    Button {
                        editMode?.wrappedValue = .active
                    } label: {
                        Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
                    }

                    Button {
                        newFolderName = documentStore.availableFolderName(in: folder)
                        isCreateFolderPresented = true
                    } label: {
                        Label(
                            .localizable(.fileHomeButtonCreateNewFolder),
                            systemSymbol: .folderBadgePlus
                        )
                    }
                    .disabled(
                        isCreatingFolder
                            || !documentStore.capabilities(for: folder).contains(.createChildren)
                    )
                }

                Section {
                    Picker("", selection: $layoutState.compactBrowserLayout) {
                        Label(
                            .localizable(.compactBrowserLayoutGrid),
                            systemSymbol: .squareGrid2x2
                        )
                        .tag(LayoutState.CompactBrowserLayout.grid)

                        Label(
                            .localizable(.compactBrowserLayoutList),
                            systemSymbol: .listDash
                        )
                        .tag(LayoutState.CompactBrowserLayout.list)
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                    .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var folderActionsMenu: some View {
        let label = HStack(spacing: 6) {
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemSymbol: .chevronDownCircleFill)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 150)

        if folder.isLocationRoot {
            label.modifier(
                CloudStorageLocationActionsModifier(
                    location: folder.location,
                    presentation: .fileHomeMenu,
                    showsSelection: false
                )
            )
        } else {
            label.modifier(
                CloudStorageFolderActionsModifier(
                    folder: folder,
                    presentation: .fileHomeMenu,
                    showsSelection: false
                )
            )
        }
    }

    private var allFilesAreSelected: Bool {
        !files.isEmpty
            && fileState.selectedCloudStorageFiles == fileReferences
    }

    private func toggleSelectAllFiles() {
        if allFilesAreSelected {
            fileState.selectedCloudStorageFiles = []
        } else {
            fileState.selectedCloudStorageFiles = fileReferences
        }
    }

    private var fileReferences: Set<CloudStorageDocumentReference> {
        Set(files.compactMap { file in
            guard case .cloudStorageFile(let reference) = file else { return nil }
            return reference
        })
    }

    private func deleteSelectedFiles() {
        let references = fileState.selectedCloudStorageFiles
        guard !references.isEmpty else { return }
        Task {
            do {
                guard await fileState.closeActiveFileIfDeleting(anyOf: references) else {
                    return
                }
                try await documentStore.deleteDocuments(
                    references,
                    connections: connections
                )
                fileState.resetSelections()
                editMode?.wrappedValue = .inactive
            } catch {
                alertToast(error)
            }
        }
    }

    private func createFolder(named name: String) {
        guard !isCreatingFolder else { return }
        isCreatingFolder = true
        Task { @MainActor in
            defer { isCreatingFolder = false }
            do {
                _ = try await documentStore.createFolder(
                    named: name,
                    in: folder,
                    connections: connections
                )
            } catch {
                alertToast(error)
            }
        }
    }
}
#endif
