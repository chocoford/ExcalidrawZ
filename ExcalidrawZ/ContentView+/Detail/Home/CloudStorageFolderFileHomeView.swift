//
//  CloudStorageFolderFileHomeView.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI

struct CloudStorageFolderFileHomeView: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    let folder: CloudStorageFolderReference

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared
    @StateObject private var browser: CloudStorageSidebarBrowserModel
    @StateObject private var connections: CloudStorageConnectionStore
    @State private var selection: String?
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#endif

    private let fileItemWidth: CGFloat = 240
    private let folderItemWidth: CGFloat = 220

    init(folder: CloudStorageFolderReference) {
        self.folder = folder
        self._browser = StateObject(
            wrappedValue: CloudStorageSidebarBrowserModel(location: folder.location)
        )
        self._connections = StateObject(wrappedValue: .shared)
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
        FileHomeContainer {
            containerContent
        }
        .showPlaceholder(items?.isEmpty == true, itemWidth: fileItemWidth)
        .contentBackground {
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

    private var containerContent: some View {
        VStack(spacing: 30) {
            header
                .padding(.horizontal, 20)

            quickActions
                .padding(.horizontal, 30)

            groupsAndFiles
                .padding(.horizontal, 30)
        }
        .padding(.top, parentFolders.isEmpty ? 36 : 15)
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

    private var folderPath: [CloudStorageFolderReference] {
        documentStore.folderPath(for: folder)
    }

    private var parentFolders: [CloudStorageFolderReference] {
        Array(folderPath.dropLast())
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(parentFolders) { parent in
                    Button {
                        fileState.setActiveFile(nil)
                        fileState.setActiveGroupIfNeeded(.cloudStorageFolder(parent))
                    } label: {
                        Text(parent.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.text(size: .small))

                    if parent != parentFolders.last {
                        Image(systemSymbol: .chevronRight)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .font(.caption)

            HStack {
                Text(folder.name)
                    .font(.title)
                Spacer()

                if let errorMessage = browser.errorMessage {
#if os(macOS)
                    if #available(macOS 14.0, *) {
                        retryButton(errorMessage: errorMessage)
                            .buttonStyle(.accessoryBar)
                    } else {
                        retryButton(errorMessage: errorMessage)
                    }
#else
                    retryButton(errorMessage: errorMessage)
                        .modernButtonStyle(style: .glass, shape: .circle)
#endif
                }

                actionsMenu
            }
            .padding(.horizontal, 10)
        }
    }

    private func retryButton(errorMessage: String) -> some View {
        Button {
            Task {
                await CloudStorageSyncService.shared.prioritizeDocuments(
                    in: folder.location,
                    parentID: folder.itemID,
                    connections: connections
                )
                if let errorMessage = browser.errorMessage {
                    alertToast(CloudStorageError.transport(errorMessage))
                }
            }
        } label: {
            Image(systemSymbol: .arrowClockwise)
        }
        .help(errorMessage)
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 10) {
            NewFileButton(usesFileHomeOpenTransition: true)

            NewGroupButton(parentID: nil)

            Spacer()
        }
        .disabled(!documentStore.capabilities(for: folder).contains(.createChildren))
#if os(iOS)
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
#else
        .modifier(FileHomeQuickActionButtonStyleModifier())
#endif
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if folder.isLocationRoot {
            styledActionsMenu(
                actionsMenuLabel.modifier(
                    CloudStorageLocationActionsModifier(
                        location: folder.location,
                        presentation: .fileHomeMenu
                    )
                )
            )
        } else {
            styledActionsMenu(
                actionsMenuLabel.modifier(
                    CloudStorageFolderActionsModifier(
                        folder: folder,
                        presentation: .fileHomeMenu
                    )
                )
            )
        }
    }

    @ViewBuilder
    private var actionsMenuLabel: some View {
        ZStack {
#if os(iOS)
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                .padding(6)
#else
            Image(systemSymbol: .ellipsisCircle)
#endif
        }
    }

    private func styledActionsMenu<MenuContent: View>(
        _ content: MenuContent
    ) -> some View {
        content
            .menuIndicator(.hidden)
#if os(iOS)
            .modernButtonStyle(style: .glass, shape: .circle)
            .labelStyle(.iconOnly)
#else
            .modifier(CloudStorageFileHomeAccessoryButtonModifier())
            .fixedSize()
#endif
    }

    @ViewBuilder
    private var groupsAndFiles: some View {
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

        FileHomeFilesGrid(
            files: files,
            itemWidth: fileItemWidth,
            contentRevision: documentStore.metadataRevision(for: folder.location.id)
        )
    }

    private func deleteSelectedFiles() {
        let references = fileState.selectedCloudStorageFiles
        guard !references.isEmpty else { return }
        Task {
            do {
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
