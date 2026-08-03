//
//  CloudStorageSidebarLocationRow.swift
//  ExcalidrawZ
//

import SwiftUI
import UniformTypeIdentifiers

struct CloudStorageSidebarLocationRow<Icon: View>: View {
    @EnvironmentObject private var fileState: FileState

    let location: CloudStorageLocation
    @ObservedObject var connections: CloudStorageConnectionStore
    let icon: Icon

    @StateObject private var browser: CloudStorageSidebarBrowserModel
    @State private var isExpanded = false

    init(
        location: CloudStorageLocation,
        connections: CloudStorageConnectionStore,
        @ViewBuilder icon: () -> Icon
    ) {
        self.location = location
        self.connections = connections
        self.icon = icon()
        self._browser = StateObject(
            wrappedValue: CloudStorageSidebarBrowserModel(location: location)
        )
    }

    var body: some View {
        SelectableDisclosureGroup(
            isSelected: selectionBinding,
            isExpanded: $isExpanded
        ) {
            CloudStorageSidebarFolderContents(
                folderID: location.rootItemID,
                browser: browser,
                connections: connections
            )
        } label: {
            HStack(spacing: 6) {
                icon
                Text(location.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if isLoadingMetadata {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else {
                    CloudStorageFolderSyncIndicator(state: folderSyncState)
                }
            }
            .contentShape(Rectangle())
            .modifier(CloudStorageLocationActionsModifier(location: location))
        }
        .disclosureGroupIndicatorVisibility(.visible)
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: {
                fileState.currentActiveGroup == .cloudStorageFolder(.root(of: location))
                    && fileState.currentActiveFile == nil
            },
            set: { selected in
                guard selected else { return }
                DispatchQueue.main.async {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(.root(of: location)))
                    fileState.setActiveFile(nil)
                }
            }
        )
    }

    private var isLoadingMetadata: Bool {
        browser.isRefreshing
            && browser.items(
                in: location.rootItemID,
                sortedBy: fileState.sortField
            ) == nil
    }

    private var folderSyncState: CloudStorageFolderSyncState {
        browser.folderSyncState(in: location.rootItemID)
    }
}

private struct CloudStorageSidebarFolderContents: View {
    @EnvironmentObject private var fileState: FileState

    let folderID: CloudStorageItemID
    @ObservedObject var browser: CloudStorageSidebarBrowserModel
    @ObservedObject var connections: CloudStorageConnectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items == nil {
                if let errorMessage = browser.errorMessage,
                   !browser.isRefreshing {
                    statusRow {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorMessage)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button {
                            Task {
                                await browser.refresh(connections: connections)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    statusRow {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Loading")
                    }
                }
            } else if let items {
                if items.isEmpty {
                    statusRow {
                        Text("No Excalidraw Files")
                    }
                } else {
                    ForEach(items) { item in
                        if item.kind == .folder {
                            CloudStorageSidebarFolderRow(
                                folder: item,
                                browser: browser,
                                connections: connections
                            )
                        } else {
                            CloudStorageSidebarFileRow(
                                item: item,
                                browser: browser
                            )
                        }
                    }
                }
            }
        }
        .task(id: folderID) {
            if items == nil {
                await browser.refresh(connections: connections, force: false)
            }
            CloudStorageSyncService.shared.prioritizeDocuments(
                in: browser.location,
                parentID: folderID,
                connections: connections
            )
        }
    }

    private var items: [CloudStorageItem]? {
        browser.items(in: folderID, sortedBy: fileState.sortField)
    }

    private func statusRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 22)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CloudStorageSidebarFolderRow: View {
    @EnvironmentObject private var fileState: FileState

    let folder: CloudStorageItem
    @ObservedObject var browser: CloudStorageSidebarBrowserModel
    @ObservedObject var connections: CloudStorageConnectionStore

    @State private var isExpanded = false

    var body: some View {
        SelectableDisclosureGroup(
            isSelected: selectionBinding,
            isExpanded: $isExpanded
        ) {
            CloudStorageSidebarFolderContents(
                folderID: folder.id,
                browser: browser,
                connections: connections
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(folder.name)
                Spacer(minLength: 4)
                CloudStorageFolderSyncIndicator(
                    state: browser.folderSyncState(in: folder.id)
                )
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .contentShape(Rectangle())
            .modifier(CloudStorageFolderActionsModifier(folder: reference))
        }
        .disclosureGroupIndicatorVisibility(.visible)
    }

    private var reference: CloudStorageFolderReference {
        CloudStorageFolderReference(location: browser.location, item: folder)
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: {
                fileState.currentActiveGroup == .cloudStorageFolder(reference)
                    && fileState.currentActiveFile == nil
            },
            set: { selected in
                guard selected else { return }
                DispatchQueue.main.async {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(reference))
                    fileState.setActiveFile(nil)
                }
            }
        )
    }
}

private struct CloudStorageSidebarFileRow: View {
    @EnvironmentObject private var fileState: FileState

    let item: CloudStorageItem
    @ObservedObject var browser: CloudStorageSidebarBrowserModel

    var body: some View {
        FileRowButton(
            isSelected: fileState.currentActiveFile == .cloudStorageFile(reference),
            isMultiSelected: false,
            onTap: open
        ) {
            FileRowLabel(
                name: displayName,
                fileType: reference.fileType,
                updatedAt: item.modifiedAt ?? .distantPast
            ) {
                CloudStorageDocumentSyncIndicator(reference: reference)
            }
        }
        .modifier(CloudStorageFileContextMenuModifier(reference: reference))
    }

    private var reference: CloudStorageDocumentReference {
        CloudStorageDocumentReference(
            locationID: browser.location.id,
            providerID: browser.location.providerID,
            accountID: browser.location.accountID,
            itemID: item.id,
            lastKnownName: item.name,
            lastKnownModifiedAt: item.modifiedAt
        )
    }

    private func open() {
        if let parent = browser.parentFolder(for: reference) {
            fileState.setActiveGroupIfNeeded(.cloudStorageFolder(parent))
        }
        fileState.setActiveFile(.cloudStorageFile(reference))
    }

    private var displayName: String {
        let name = item.name as NSString
        let extensionName = name.pathExtension.lowercased()
        let withoutLastExtension = name.deletingPathExtension as NSString

        if ["png", "svg"].contains(extensionName),
           withoutLastExtension.pathExtension.lowercased() == "excalidraw" {
            return withoutLastExtension.deletingPathExtension
        }
        return withoutLastExtension as String
    }
}

private struct CloudStorageFolderSyncIndicator: View {
    let state: CloudStorageFolderSyncState

    @ViewBuilder
    var body: some View {
        switch state {
            case .synchronizing:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            case .queued:
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
        }
    }
}

private extension CloudStorageDocumentReference {
    var fileType: UTType {
        let pathExtension = (lastKnownName as NSString).pathExtension.lowercased()
        return pathExtension == "svg"
            ? .excalidrawSVG
            : pathExtension == "png"
            ? .excalidrawPNG
            : .excalidrawFile
    }
}
