//
//  CloudStorageFolderFileHomeView.swift
//  ExcalidrawZ
//

import SwiftUI
import SwiftyAlert
import ChocofordUI

struct CloudStorageFolderFileHomeView: View {
    @AppStorage("googleDriveAccessHintDismissed.v1") private var isGoogleDriveAccessHintDismissed = false
    @Environment(\.alertToast) private var alertToast
    @Environment(FileState.self) private var fileState

    let folder: CloudStorageFolderReference

    @Bindable private var documentStore = CloudStorageDocumentStore.shared
    @State private var browser: CloudStorageSidebarBrowserModel
    @State private var connections: CloudStorageConnectionStore
    @State private var selection: String?
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#endif

    private let fileItemWidth: CGFloat = 240
    private let folderItemWidth: CGFloat = 220

    init(folder: CloudStorageFolderReference) {
        self.folder = folder
        self._browser = State(
            initialValue: CloudStorageSidebarBrowserModel(location: folder.location)
        )
        self._connections = State(initialValue: .shared)
    }

    var body: some View {
        ZStack {
            if #available(macOS 13.0, iOS 15.0, *) {
                content
                    .scrollContentBackground(.hidden)
            } else {
                content
            }
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
        }
    }

    private var content: some View {
        FileHomeGridContainer(
            files: files,
            itemWidth: fileItemWidth,
            contentRevision: documentStore.metadataRevision(for: folder.location.id),
            showsPlaceholder: items?.isEmpty == true,
            headerSpacing: fileGridHeaderSpacing
        ) {
            containerHeader
        } background: {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = nil
                    fileState.resetSelections()
                }
        }
        .overlay {
            if items == nil, browser.errorMessage == nil {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: folder.id) {
            await CloudStorageSyncService.shared.prioritizeDocuments(
                in: folder.location,
                parentID: folder.itemID,
                connections: connections
            )
        }
#if os(iOS)
        .overlay(alignment: .bottom) {
            if editMode.isEditing, !fileState.selectedCloudStorageFiles.isEmpty {
                Button(role: .destructive) {
                    deleteSelectedFiles()
                } label: {
                    Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                }
                .modernButtonStyle(style: .glassProminent, shape: .capsule)
                .padding(.bottom, 12)
            }
        }
        .environment(\.editMode, $editMode)
#endif
    }

    private var containerHeader: some View {
        VStack(spacing: 30) {
#if os(iOS)
            quickActions
                .padding(.horizontal, 30)
#endif

            if let errorMessage = browser.errorMessage {
                HStack {
                    Spacer()
                    retryButton(errorMessage: errorMessage)
#if os(macOS)
                        .modifier(CloudStorageFileHomeAccessoryButtonModifier())
#else
                        .modernButtonStyle(style: .glass, shape: .circle)
#endif
                }
                .padding(.horizontal, 30)
            }

            if showsGoogleDriveAccessBanner {
                GoogleDriveAccessBanner(folder: folder) {
                    isGoogleDriveAccessHintDismissed = true
                }
                .padding(.horizontal, 30)
            }

            if !childFolders.isEmpty {
                childFolderGrid
                    .padding(.horizontal, 30)
            }
        }
        .padding(.top, 36)
    }

    private var showsGoogleDriveAccessBanner: Bool {
        folder.location.providerID == .googleDrive && !isGoogleDriveAccessHintDismissed
    }

    private var fileGridHeaderSpacing: CGFloat {
#if os(macOS)
        showsGoogleDriveAccessBanner || !childFolders.isEmpty || browser.errorMessage != nil ? 30 : 0
#else
        30
#endif
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

    private func retryButton(errorMessage: String) -> some View {
        Button {
            Task {
                await CloudStorageSyncService.shared.prioritizeDocumentsAfterUserEntry(
                    in: folder.location,
                    parentID: folder.itemID,
                    connections: connections
                )
                if let errorMessage = browser.errorMessage {
                    alertToast(.init(displayMode: .hud, type: .error(.red), title: errorMessage))
                }
            }
        } label: {
            Image(systemSymbol: .arrowClockwise)
        }
        .help(errorMessage)
    }

#if os(iOS)
    private var quickActions: some View {
        HStack(spacing: 10) {
            NewFileButton(usesFileHomeOpenTransition: true)

            NewGroupButton(
                type: .cloudStorageFolder,
                parentID: nil,
                cloudStorageParent: folder
            )

            if editMode.isEditing {
                Button {
                    withAnimation(.smooth) {
                        editMode = .inactive
                    }
                    fileState.resetSelections()
                } label: {
                    Image(systemSymbol: .checkmark)
                        .padding(6)
                }
                .modernButtonStyle(style: .glassProminent, size: .regular, shape: .circle)
            } else {
                actionsMenu
            }

            Spacer()
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
    }

    private var actionsMenu: some View {
        CloudStorageFileHomeActionsMenu(folder: folder)
            .modernButtonStyle(style: .glass, shape: .circle)
            .fixedSize()
    }
#endif

    @ViewBuilder
    private var childFolderGrid: some View {
        LazyVGrid(
            columns: [
                .init(
                    .adaptive(
                        minimum: folderItemWidth,
                        maximum: folderItemWidth * 2 - 0.1
                    ),
                    spacing: 20
                )
            ],
            spacing: 20
        ) {
            ForEach(childFolders) { item in
                let reference = CloudStorageFolderReference(
                    location: folder.location,
                    item: item
                )
                HomeFolderItemView(
                    isSelected: selection == reference.id,
                    isHighlighted: false,
                    name: item.name,
                    itemsCount: browser.items(
                        in: item.id,
                        sortedBy: fileState.sortField
                    )?.count ?? 0,
                    isLoading: browser.folderSyncState(in: item.id) == .synchronizing
                )
                .modifier(CloudStorageFolderActionsModifier(folder: reference))
#if os(macOS)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(reference))
                })
                .simultaneousGesture(TapGesture().onEnded {
                    selection = reference.id
                    fileState.resetSelections()
                })
#else
                .onTapGesture {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(reference))
                }
#endif
            }
        }
        .watch(value: fileState.selectedCloudStorageFiles.isEmpty) { isEmpty in
            if !isEmpty { selection = nil }
        }
    }

    private func deleteSelectedFiles() {
        let references = fileState.selectedCloudStorageFiles
        guard !references.isEmpty else { return }
        Task {
            do {
                guard await fileState.closeActiveFileIfDeleting(
                    anyOf: references
                ) else {
                    return
                }
                try await documentStore.deleteDocuments(
                    references,
                    connections: connections
                )
                fileState.resetSelections()
#if os(iOS)
                editMode = .inactive
#endif
            } catch {
                alertToast(error)
            }
        }
    }
}

/// Shared by the macOS toolbar and the iOS file-home action row.
struct CloudStorageFileHomeActionsMenu: View {
    let folder: CloudStorageFolderReference

    var body: some View {
        SwiftUI.Group {
            if folder.isLocationRoot {
                menuLabel.modifier(
                    CloudStorageLocationActionsModifier(
                        location: folder.location,
                        presentation: .fileHomeMenu
                    )
                )
            } else {
                menuLabel.modifier(
                    CloudStorageFolderActionsModifier(
                        folder: folder,
                        presentation: .fileHomeMenu
                    )
                )
            }
        }
        .menuIndicator(.hidden)
        .labelStyle(.iconOnly)
    }

    private var menuLabel: some View {
        Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
#if os(iOS)
            .padding(6)
#endif
    }
}

private struct CloudStorageFileHomeAccessoryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            content.buttonStyle(.accessoryBar)
        } else {
            content
        }
#else
        content
#endif
    }
}
